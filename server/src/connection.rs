use crate::{
    protocol::{NewBlock, Request, MAX_LINE_BYTES, MAX_PUBLISH_LINE_BYTES},
    server::ChatServer,
};
use std::sync::Arc;
use tokio::{
    io::{AsyncBufReadExt, AsyncReadExt, AsyncWriteExt, BufReader},
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
    let receive = async {
        loop {
            let mut line = Vec::new();
            let count = (&mut reader)
                .take((MAX_LINE_BYTES + 1) as u64)
                .read_until(b'\n', &mut line)
                .await?;
            if count == 0 {
                return Ok::<(), std::io::Error>(());
            }
            if count > MAX_PUBLISH_LINE_BYTES || line.last() != Some(&b'\n') {
                break;
            }
            let request = serde_json::from_slice(&line);
            let Ok(Request::Publish { block }) = request else {
                break;
            };
            if block.is_empty() {
                break;
            }
            let publish_result = server.publish(block).await;
            if publish_result.is_err() {
                break;
            }
        }
        Ok(())
    };
    let send = async {
        // A lagging receiver is disconnected instead of silently losing blocks.
        loop {
            let event = events.recv().await;
            let Ok(record) = event else {
                break;
            };
            let mut bytes = serde_json::to_vec(&record)?;
            bytes.push(b'\n');
            writer.write_all(&bytes).await?;
        }
        Ok::<(), std::io::Error>(())
    };
    tokio::select! {
        _ = token.cancelled() => {},
        _ = receive => {},
        _ = send => {},
    }
}
