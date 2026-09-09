# PaChat server

Rust TCP relay. It stores opaque blocks and broadcasts each newly stored block to every currently connected client, including the publisher. It does not register users, exchange keys, decrypt content, or route by recipient.

## Run

From `server/`:

```sh
cargo run -- --host 0.0.0.0 --port 9000
```

Or `docker compose up --build`. Default address: `0.0.0.0:9000`.

## Protocol

UTF-8 JSON, one LF-terminated object per line. Only two message types exist.

Client → server:

```json
{"type":"publish","block":"opaque-string"}
```

Server → all currently connected clients:

```json
{"type":"new_block","id":1,"block":"opaque-string"}
```

The server preserves the string value exactly. Flutter uses Base64-encoded JSON containing a version and encrypted copies, but the relay does not inspect that format. No names, public keys, sender IDs, or recipient IDs appear in the transport protocol.

IDs start at 1 and increase in storage order. Saving and broadcasting are ordered together. A `new_block` is emitted only after storage succeeds. Connecting does not replay stored blocks. Disconnecting clients miss subsequent blocks.

Empty blocks, malformed requests, unsupported operations, storage errors, and lagging broadcast receivers cause connection closure. There is deliberately no third error operation in this prototype.

## Storage and lifecycle

`BlockStore` owns append and ID allocation. `InMemoryBlockStore` keeps all records until the process exits. `ChatServer::with_store` injects an implementation; storage has no dependency on sockets or friend keys. History retrieval is intentionally absent from the current interface.

A bounded broadcast queue allows independent clients to receive without waiting for a slow client. A lagging receiver is disconnected rather than silently skipping records. Ctrl+C closes the listener and active connections.

The server still observes network connections, IP addresses, publication times, and sizes. It provides neither transport anonymity nor authentication. In-memory history is currently unbounded, appropriate for small tests rather than an unrestricted public relay.

## Checks

```sh
cargo fmt --check
cargo test
cargo build
```

The network test verifies publication without a handshake, delivery to sender and another client, and no history on a new connection. The Flutter client also contains a cross-language integration test; see `../client/README.md`.
