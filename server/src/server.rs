use crate::{
    protocol::NewBlock,
    store::{BlockStore, InMemoryBlockStore},
};
use std::{io, net::SocketAddr, sync::Arc};
use tokio::{
    net::TcpListener,
    sync::{broadcast, Mutex},
    task::JoinSet,
};
use tokio_util::sync::CancellationToken;

pub struct ChatServer {
    addr: SocketAddr,
    store: Mutex<Box<dyn BlockStore>>,
    events: broadcast::Sender<NewBlock>,
}

impl ChatServer {
    pub fn new(host: &str, port: u16) -> Self {
        Self::with_store(
            format!("{host}:{port}").parse().expect("invalid address"),
            Box::new(InMemoryBlockStore::default()),
        )
    }

    pub fn with_store(addr: SocketAddr, store: Box<dyn BlockStore>) -> Self {
        Self {
            addr,
            store: Mutex::new(store),
            events: broadcast::channel(128).0,
        }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<NewBlock> {
        self.events.subscribe()
    }

    pub async fn publish(&self, block: String) -> Result<(), String> {
        // Keep allocation, storage and publication in the same order.
        let mut store = self.store.lock().await;
        let record = store.append(block)?;
        let _ = self.events.send(record);
        Ok(())
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
    use std::time::Duration;
    use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
    use tokio::net::TcpStream;

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
            assert!(tokio::time::timeout(
                Duration::from_millis(100),
                c.read_line(&mut String::new())
            )
            .await
            .is_err());
            token.cancel();
            task.await.unwrap().unwrap();
        })
        .await
        .unwrap();
    }
}
