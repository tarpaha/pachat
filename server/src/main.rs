mod connection;
mod protocol;
mod server;
mod sqlite_store;
mod store;

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
    /// SQLite file, relative to the current working directory.
    #[arg(long, default_value = "data/pachat.db")]
    database: std::path::PathBuf,
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
    let store = match sqlite_store::SqliteBlockStore::open(&args.database) {
        Ok(store) => store,
        Err(error) => {
            eprintln!(
                "Could not open database {}: {error}",
                args.database.display()
            );
            std::process::exit(1);
        }
    };
    let server = Arc::new(ChatServer::with_store(
        format!("{}:{}", args.host, args.port)
            .parse()
            .expect("invalid address"),
        Box::new(store),
    ));
    if let Err(error) = server.run(token).await {
        eprintln!("Server failed: {error}");
        std::process::exit(1);
    }
}
