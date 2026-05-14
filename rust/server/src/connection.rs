use std::sync::Arc;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader, BufWriter};
use tokio::net::TcpStream;
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;

use crate::protocol::{self, Message};
use crate::server::ChatServer;

pub async fn handle(stream: TcpStream, server: Arc<ChatServer>, token: CancellationToken) {
    let (read_half, write_half) = stream.into_split();

    let (tx, mut rx) = mpsc::channel::<String>(32);

    let write_token = token.clone();
    tokio::spawn(async move {
        let mut writer = BufWriter::new(write_half);
        loop {
            tokio::select! {
                _ = write_token.cancelled() => break,
                msg = rx.recv() => {
                    match msg {
                        Some(line) => {
                            if writer.write_all(line.as_bytes()).await.is_err() { break; }
                            if writer.write_all(b"\n").await.is_err() { break; }
                            if writer.flush().await.is_err() { break; }
                        }
                        None => break,
                    }
                }
            }
        }
    });

    let send = |msg: &Message, tx: mpsc::Sender<String>| {
        let line = protocol::serialize(msg);
        async move {
            let _ = tx.send(line).await;
        }
    };

    let mut lines = BufReader::new(read_half).lines();
    let mut registered_nick: Option<String> = None;

    'outer: {
        // Handshake
        let first_line = tokio::select! {
            _ = token.cancelled() => break 'outer,
            result = lines.next_line() => match result {
                Ok(Some(l)) => l,
                _ => break 'outer,
            }
        };

        match protocol::deserialize(&first_line) {
            Err(_) => {
                send(
                    &Message::Error {
                        code: "PROTOCOL_ERROR".into(),
                        text: "Malformed JSON.".into(),
                    },
                    tx.clone(),
                )
                .await;
                break 'outer;
            }
            Ok(Message::Connect {
                nickname,
                publickey,
            }) => {
                let nick = nickname.trim().to_string();
                if nick.is_empty() || nick.len() > 32 {
                    send(
                        &Message::Error {
                            code: "NICKNAME_INVALID".into(),
                            text: "Nickname must be 1–32 characters.".into(),
                        },
                        tx.clone(),
                    )
                    .await;
                    break 'outer;
                }
                if !server.try_register(&nick, tx.clone()).await {
                    send(
                        &Message::Error {
                            code: "NICKNAME_TAKEN".into(),
                            text: format!("The nickname '{}' is already in use.", nick),
                        },
                        tx.clone(),
                    )
                    .await;
                    break 'outer;
                }
                registered_nick = Some(nick.clone());
                server
                    .broadcast(
                        &Message::PeerJoined {
                            nickname: nick.clone(),
                            publickey,
                        },
                        Some(&nick),
                    )
                    .await;
            }
            Ok(_) => {
                send(
                    &Message::Error {
                        code: "NOT_AUTHENTICATED".into(),
                        text: "Expected connect message first.".into(),
                    },
                    tx.clone(),
                )
                .await;
                break 'outer;
            }
        }

        let nick = registered_nick.as_deref().unwrap();

        // Message loop
        loop {
            let line = tokio::select! {
                _ = token.cancelled() => break,
                result = lines.next_line() => match result {
                    Ok(Some(l)) => l,
                    _ => break,
                }
            };

            match protocol::deserialize(&line) {
                Err(_) => {
                    send(
                        &Message::Error {
                            code: "PROTOCOL_ERROR".into(),
                            text: "Malformed JSON.".into(),
                        },
                        tx.clone(),
                    )
                    .await;
                }
                Ok(msg @ Message::PeerHello { .. }) | Ok(msg @ Message::Chat { .. }) => {
                    server.route(nick, msg).await;
                }
                Ok(_) => {
                    send(
                        &Message::Error {
                            code: "PROTOCOL_ERROR".into(),
                            text: "Unexpected message type.".into(),
                        },
                        tx.clone(),
                    )
                    .await;
                }
            }
        }
    }

    if let Some(nick) = registered_nick {
        server.unregister(&nick).await;
        server
            .broadcast(&Message::PeerLeft { nickname: nick }, None)
            .await;
    }
}
