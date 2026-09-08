use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;

use tokio::net::TcpListener;
use tokio::sync::{mpsc, RwLock};
use tokio_util::sync::CancellationToken;

use crate::protocol::{self, Message};

pub struct ChatServer {
    addr: SocketAddr,
    clients: RwLock<HashMap<String, mpsc::Sender<String>>>,
}

impl ChatServer {
    pub fn new(host: &str, port: u16) -> Self {
        let addr: SocketAddr = format!("{}:{}", host, port).parse().expect("invalid address");
        ChatServer {
            addr,
            clients: RwLock::new(HashMap::new()),
        }
    }

    pub async fn run(self: Arc<Self>, token: CancellationToken) {
        let listener = TcpListener::bind(self.addr).await.expect("failed to bind");
        println!("Server listening on {}", self.addr);

        let mut handles = Vec::new();

        loop {
            tokio::select! {
                _ = token.cancelled() => break,
                result = listener.accept() => {
                    match result {
                        Ok((stream, _)) => {
                            stream.set_nodelay(true).ok();
                            let server = Arc::clone(&self);
                            let child = token.child_token();
                            let handle = tokio::spawn(crate::connection::handle(stream, server, child));
                            handles.push(handle);
                        }
                        Err(_) => break,
                    }
                }
            }
        }

        for handle in handles {
            let _ = handle.await;
        }
    }

    pub async fn try_register(&self, nick: &str, tx: mpsc::Sender<String>) -> bool {
        let key = nick.to_lowercase();
        let mut clients = self.clients.write().await;
        if clients.contains_key(&key) {
            return false;
        }
        clients.insert(key, tx);
        true
    }

    pub async fn unregister(&self, nick: &str) {
        let key = nick.to_lowercase();
        self.clients.write().await.remove(&key);
    }

    pub async fn broadcast(&self, msg: &Message, exclude: Option<&str>) {
        let line = protocol::serialize(msg);
        let senders: Vec<mpsc::Sender<String>> = {
            let clients = self.clients.read().await;
            clients
                .iter()
                .filter(|(nick, _)| {
                    exclude.map_or(true, |e| !nick.eq_ignore_ascii_case(e))
                })
                .map(|(_, tx)| tx.clone())
                .collect()
        };
        for tx in senders {
            let _ = tx.send(line.clone()).await;
        }
    }

    pub async fn route(&self, sender_nick: &str, msg: Message) {
        let to = match msg.to_field() {
            Some(t) => t.to_lowercase(),
            None => return,
        };
        let forwarded = protocol::serialize(&msg.with_from(sender_nick.to_string()));
        let tx = {
            let clients = self.clients.read().await;
            clients.get(&to).cloned()
        };
        if let Some(tx) = tx {
            let _ = tx.send(forwarded).await;
        }
    }
}
