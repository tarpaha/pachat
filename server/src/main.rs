mod connection;
mod protocol;
mod server;

use std::sync::Arc;

use clap::Parser;
use tokio_util::sync::CancellationToken;

use server::ChatServer;

#[derive(Parser)]
struct Args {
    #[arg(long, default_value = "0.0.0.0")]
    host: String,
    #[arg(long, default_value_t = 9000)]
    port: u16,
}

#[tokio::main]
async fn main() {
    let args = Args::parse();
    let token = CancellationToken::new();
    let t = token.clone();
    tokio::spawn(async move {
        tokio::signal::ctrl_c().await.ok();
        t.cancel();
    });
    let server = Arc::new(ChatServer::new(&args.host, args.port));
    server.run(token).await;
}
