use crate::{protocol::NewBlock, store::BlockStore};
use std::{io, net::SocketAddr, sync::Arc};
use tokio::{
    net::TcpListener,
    sync::{broadcast, Mutex},
    task::JoinSet,
};
use tokio_util::sync::CancellationToken;

pub struct ChatServer {
    pub database_id: String,
    addr: SocketAddr,
    store: Arc<Mutex<Box<dyn BlockStore>>>,
    events: broadcast::Sender<NewBlock>,
}

impl ChatServer {
    pub fn with_store(addr: SocketAddr, store: Box<dyn BlockStore>) -> Self {
        Self {
            database_id: store.database_id().to_owned(),
            addr,
            store: Arc::new(Mutex::new(store)),
            events: broadcast::channel(128).0,
        }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<NewBlock> {
        self.events.subscribe()
    }

    pub async fn publish(&self, block: String) -> Result<(), String> {
        // Keep allocation, storage and publication in the same order.
        let mut store = self.store.clone().lock_owned().await;
        let events = self.events.clone();
        tokio::task::spawn_blocking(move || {
            let record = store.append(block)?;
            let _ = events.send(record);
            Ok(())
        })
        .await
        .map_err(|e| e.to_string())?
    }

    pub async fn history(
        &self,
        after_id: u64,
    ) -> Result<(Vec<NewBlock>, broadcast::Receiver<NewBlock>), String> {
        let store = self.store.clone().lock_owned().await;
        let events = self.events.clone();
        // Snapshot and subscription share the publication lock: no gap or overlap.
        tokio::task::spawn_blocking(move || Ok((store.page_after(after_id)?, events.subscribe())))
            .await
            .map_err(|e| e.to_string())?
    }

    pub async fn run(self: Arc<Self>, token: CancellationToken) -> io::Result<()> {
        let listener = TcpListener::bind(self.addr).await?;
        println!("Server listening on {}", listener.local_addr()?);
        self.serve(listener, token).await
    }

    async fn serve(
        self: Arc<Self>,
        listener: TcpListener,
        token: CancellationToken,
    ) -> io::Result<()> {
        let mut tasks = JoinSet::new();
        let result = loop {
            tokio::select! {
                _ = token.cancelled() => break Ok(()),
                Some(_) = tasks.join_next(), if !tasks.is_empty() => {},
                accepted = listener.accept() => {
                    let (stream, _) = match accepted { Ok(value) => value, Err(e) => break Err(e) };
                    let events = self.subscribe();
                    tasks.spawn(crate::connection::handle(stream, self.clone(), events, token.child_token()));
                }
            }
        };
        tasks.abort_all();
        while tasks.join_next().await.is_some() {}
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::InMemoryBlockStore;
    use std::time::Duration;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
    use tokio::net::TcpStream;

    #[tokio::test]
    async fn paginated_history_and_concurrent_publications_have_no_gap() {
        tokio::time::timeout(Duration::from_secs(10), async {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let server = Arc::new(ChatServer::with_store(
                addr,
                Box::new(InMemoryBlockStore::default()),
            ));
            for id in 1..=350 {
                server.publish(format!("block-{id}")).await.unwrap();
            }
            let token = CancellationToken::new();
            let task = tokio::spawn(server.clone().serve(listener, token.clone()));
            let mut client = BufReader::new(TcpStream::connect(addr).await.unwrap());
            client.read_line(&mut String::new()).await.unwrap();
            client
                .get_mut()
                .write_all(b"{\"type\":\"history\",\"after_id\":0}\n")
                .await
                .unwrap();
            let publisher = tokio::spawn({
                let server = server.clone();
                async move {
                    for id in 351..=400 {
                        server.publish(format!("block-{id}")).await.unwrap();
                    }
                }
            });
            let mut ids = Vec::new();
            let mut complete = false;
            while ids.last() != Some(&400) || !complete {
                let mut line = String::new();
                assert!(client.read_line(&mut line).await.unwrap() > 0);
                let event: serde_json::Value = serde_json::from_str(&line).unwrap();
                if event["type"] == "history_page" {
                    assert!(!complete);
                    let blocks = event["blocks"].as_array().unwrap();
                    assert!(blocks.len() <= 100);
                    ids.extend(blocks.iter().map(|b| b["id"].as_u64().unwrap()));
                    complete = event["has_more"] == false;
                } else if complete {
                    ids.push(event["id"].as_u64().unwrap());
                }
                // Live events preceding the request are replayed by history.
            }
            assert_eq!(ids, (1..=400).collect::<Vec<_>>());
            publisher.await.unwrap();
            client
                .get_mut()
                .write_all(b"{\"type\":\"history\",\"after_id\":300}\n")
                .await
                .unwrap();
            for more in [true, false] {
                let mut line = String::new();
                client.read_line(&mut line).await.unwrap();
                let page: serde_json::Value = serde_json::from_str(&line).unwrap();
                assert_eq!(page["has_more"], more);
                assert_eq!(
                    page["blocks"].as_array().unwrap().len(),
                    if more { 100 } else { 0 }
                );
                assert_eq!(page["after_id"], 400);
            }
            token.cancel();
            task.await.unwrap().unwrap();
        })
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn publishes_to_sender_and_other_client_without_handshake_or_history() {
        tokio::time::timeout(Duration::from_secs(5), async {
            let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
            let addr = listener.local_addr().unwrap();
            let server = Arc::new(ChatServer::with_store(
                addr,
                Box::new(InMemoryBlockStore::default()),
            ));
            let token = CancellationToken::new();
            let task = tokio::spawn(server.clone().serve(listener, token.clone()));
            let mut a = BufReader::new(TcpStream::connect(addr).await.unwrap());
            let mut b = BufReader::new(TcpStream::connect(addr).await.unwrap());
            for client in [&mut a, &mut b] {
                let mut line = String::new();
                client.read_line(&mut line).await.unwrap();
                let info: serde_json::Value = serde_json::from_str(&line).unwrap();
                assert_eq!(info["type"], "server_info");
                assert_eq!(info["database_id"], server.database_id);
            }
            while server.events.receiver_count() != 2 {
                tokio::task::yield_now().await;
            }
            a.get_mut()
                .write_all(b"{\"type\":\"publish\",\"block\":\"opaque\"}\n")
                .await
                .unwrap();
            for client in [&mut a, &mut b] {
                let mut line = String::new();
                client.read_line(&mut line).await.unwrap();
                let event: NewBlock = serde_json::from_str(&line).unwrap();
                assert_eq!(event.id, 1);
                assert_eq!(event.block, "opaque");
                assert_eq!(event.kind, "new_block");
            }
            let mut c = BufReader::new(TcpStream::connect(addr).await.unwrap());
            c.read_line(&mut String::new()).await.unwrap();
            assert!(tokio::time::timeout(
                Duration::from_millis(100),
                c.read_line(&mut String::new())
            )
            .await
            .is_err());
            c.get_mut().write_all(b"{\"type\":\"history\",\"after_id\":0}\n").await.unwrap();
            let mut line = String::new();
            c.read_line(&mut line).await.unwrap();
            let page: serde_json::Value = serde_json::from_str(&line).unwrap();
            assert_eq!(page["blocks"][0]["id"], 1);
            assert_eq!(page["after_id"], 1);
            assert_eq!(page["has_more"], false);
            c.get_mut().write_all(b"{\"type\":\"history\",\"after_id\":1}\n{\"type\":\"publish\",\"block\":\"live\"}\n").await.unwrap();
            line.clear();
            c.read_line(&mut line).await.unwrap();
            let page: serde_json::Value = serde_json::from_str(&line).unwrap();
            assert_eq!(page["blocks"], serde_json::json!([]));
            assert_eq!(page["has_more"], false);
            line.clear();
            c.read_line(&mut line).await.unwrap();
            assert_eq!(serde_json::from_str::<NewBlock>(&line).unwrap().id, 2);
            token.cancel();
            task.await.unwrap().unwrap();
        })
        .await
        .unwrap();
    }
}
