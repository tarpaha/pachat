use serde_json::{json, Value};
use std::{
    io::{BufRead, BufReader, Write},
    net::TcpStream,
    path::Path,
    process::{Child, Command, Stdio},
    time::Duration,
};

struct Server(Child);
impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

fn start(path: &Path) -> (Server, BufReader<TcpStream>) {
    let mut child = Server(
        Command::new(env!("CARGO_BIN_EXE_pachat-server"))
            .args(["--host", "127.0.0.1", "--port", "0", "--database"])
            .arg(path)
            .stdout(Stdio::piped())
            .spawn()
            .unwrap(),
    );
    let mut line = String::new();
    BufReader::new(child.0.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    let addr = line.trim().strip_prefix("Server listening on ").unwrap();
    let socket = TcpStream::connect(addr).unwrap();
    socket
        .set_read_timeout(Some(Duration::from_secs(5)))
        .unwrap();
    let mut socket = BufReader::new(socket);
    let info = receive(&mut socket);
    assert_eq!(info["type"], "server_info");
    assert_eq!(info["database_id"].as_str().unwrap().len(), 32);
    (child, socket)
}

fn send(socket: &mut BufReader<TcpStream>, value: Value) {
    writeln!(socket.get_mut(), "{value}").unwrap();
}

fn receive(socket: &mut BufReader<TcpStream>) -> Value {
    let mut line = String::new();
    socket.read_line(&mut line).unwrap();
    serde_json::from_str(&line).unwrap()
}

#[test]
fn acknowledged_messages_survive_process_kill_and_ids_continue() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("data/chat.db");
    {
        let (_server, mut socket) = start(&path);
        for id in 1..=25 {
            send(
                &mut socket,
                json!({"type":"publish", "block":format!("opaque-{id}")}),
            );
            assert_eq!(receive(&mut socket)["id"], id);
        }
        // Drop kills the process without graceful SQLite shutdown.
    }
    let (_server, mut socket) = start(&path);
    send(&mut socket, json!({"type":"history", "after_id":0}));
    for id in 6..=25 {
        assert_eq!(
            receive(&mut socket),
            json!({"type":"new_block", "id":id, "block":format!("opaque-{id}")})
        );
    }
    send(&mut socket, json!({"type":"history", "after_id":25}));
    send(
        &mut socket,
        json!({"type":"publish", "block":"after restart"}),
    );
    assert_eq!(receive(&mut socket)["id"], 26);
}
