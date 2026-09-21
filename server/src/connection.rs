use crate::{
    protocol::{NewBlock, Request},
    server::ChatServer,
    store::HISTORY_PAGE_SIZE,
};
use std::sync::Arc;
use tokio::{
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::TcpStream,
    sync::broadcast,
};
use tokio_util::sync::CancellationToken;

pub async fn handle(
    stream: TcpStream,
    server: Arc<ChatServer>,
    mut events: broadcast::Receiver<NewBlock>,
    token: CancellationToken,
) {
    let _ = stream.set_nodelay(true);
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);
    let mut line = Vec::new();
    let run = async {
        let hello = serde_json::json!({"type": "server_info", "database_id": server.database_id, "history_version": 2});
        writer.write_all(format!("{hello}\n").as_bytes()).await?;
        loop {
            let records = tokio::select! {
                count = reader.read_until(b'\n', &mut line) => {
                    if count? == 0 || line.last() != Some(&b'\n') { break; }
                    let request = serde_json::from_slice::<Request>(&line);
                    line.clear();
                    match request {
                        Ok(Request::Publish { block }) if !block.is_empty() => {
                            if server.publish(block).await.is_err() { break; }
                            continue;
                        }
                        Ok(Request::History { after_id }) => {
                            let mut cursor = after_id;
                            loop {
                                let (blocks, subscription) = server.history(cursor).await
                                    .map_err(std::io::Error::other)?;
                                let has_more = blocks.len() == HISTORY_PAGE_SIZE;
                                if let Some(last) = blocks.last() { cursor = last.id; }
                                let page = serde_json::json!({
                                    "type": "history_page", "blocks": blocks,
                                    "after_id": cursor, "has_more": has_more,
                                });
                                writer.write_all(format!("{page}\n").as_bytes()).await?;
                                if !has_more {
                                    // The final page and subscription were captured under
                                    // the publication lock. Later blocks arrive live.
                                    events = subscription;
                                    break;
                                }
                            }
                            continue;
                        }
                        _ => break,
                    }
                }
                event = events.recv() => {
                    // Disconnect lagging clients instead of silently losing blocks.
                    let Ok(record) = event else { break };
                    vec![record]
                }
            };
            for record in records {
                let mut bytes = serde_json::to_vec(&record)?;
                bytes.push(b'\n');
                writer.write_all(&bytes).await?;
            }
        }
        Ok::<(), std::io::Error>(())
    };
    tokio::select! {
        _ = token.cancelled() => {},
        _ = run => {},
    }
}
