use crate::{
    protocol::{NewBlock, Request},
    server::ChatServer,
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
        let hello = serde_json::json!({"type": "server_info", "database_id": server.database_id});
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
                            let (records, subscription) = server.history(after_id).await
                                .map_err(std::io::Error::other)?;
                            events = subscription;
                            records
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
