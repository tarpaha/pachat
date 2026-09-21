# PaChat server

Rust TCP relay. It stores opaque blocks and broadcasts each newly stored block to every currently connected client, including the publisher. It does not register users, exchange keys, decrypt content, or route by recipient.

## Run

From `server/`:

```sh
cargo run -- --host 0.0.0.0 --port 9000
```

Or `docker compose up --build`. Default address: `0.0.0.0:9000`.

SQLite is bundled into the executable; Windows needs neither Docker nor a separately installed database. By default the server creates `data/pachat.db` relative to its working directory, including missing parent directories. Keep the same database file between runs. To select a different path:

```sh
cargo run -- --host 127.0.0.1 --port 9000 --database data/test.db
```

An unreadable or corrupt database causes startup to fail; it is never replaced with an empty database. Run one PaChat server per database file.

Docker Compose mounts the named volume `pachat-data` at `/app/data`, owned by the runtime user. Rebuilding/recreating the container retains history. Removing the volume (including `docker compose down -v`) deletes that history.

## Protocol

UTF-8 JSON, one LF-terminated object per line. History is requested explicitly.

The first server response on each connection identifies its database:

```json
{"type":"server_info","database_id":"9cd12c6aab8b465fafbb7e872e5b510a","history_version":2}
```

Clients select the local cache for this ID before sending the history request. Update client and server together; this handshake is required by the client.

Client → server:

```json
{"type":"publish","block":"opaque-string"}
```

Server → all currently connected clients:

```json
{"type":"new_block","id":1,"block":"opaque-string"}
```

The server preserves the string value exactly. Flutter uses Base64-encoded JSON containing a version and encrypted copies, but the relay does not inspect that format. No names, public keys, sender IDs, or recipient IDs appear in the transport protocol.

IDs start at 1 and increase in storage order. Saving and broadcasting are ordered together. A `new_block` is emitted only after storage succeeds. Clients request `{"type":"history","after_id":123}` once to stream **all** subsequent blocks in ascending order, in pages of at most 100:

```json
{"type":"history_page","blocks":[{"type":"new_block","id":124,"block":"opaque-string"}],"after_id":124,"has_more":false}
```

`after_id` is the last ID in the page, or the requested cursor for an empty page. `has_more:true` means another page follows automatically; clients do not request each page. Exactly full pages are followed by another page, which may be empty. An empty history still returns a final page. Use 0 for a new cache. Message IDs need not be consecutive if records were manually deleted.

Each page query and replacement live subscription share the publication lock. During catch-up the connection sends pages only; after the final page it switches atomically to that page's subscription. Publications during catch-up appear in a later page or in the live stream without a gap. Live events sent before the history request was handled must be ignored by a synchronizing client: the pages replay them. A dropped connection can resume from the last completely processed page. Slow live subscribers are disconnected and must reconnect and replay.

This changes the history response format. Update client and server together. `history_version:2` in the greeting lets new clients reject servers with the old, incomplete latest-20 API.

Empty blocks, malformed requests, unsupported operations, storage errors, and lagging broadcast receivers cause connection closure. There is deliberately no third error operation in this prototype.

## Storage and lifecycle

`BlockStore` owns append, ID allocation and bounded history retrieval. Production uses `SqliteBlockStore`; `InMemoryBlockStore` is only a test implementation. `ChatServer::with_store` injects storage independently of sockets or friend keys.

The `metadata` table stores a random 128-bit `database_id`, generated once and reused on every restart. A new database gets a new ID; copying a database preserves its ID.

The `blocks` table stores only `id` and the original opaque `block`. SQLite `INTEGER PRIMARY KEY AUTOINCREMENT` keeps committed IDs increasing across restarts and prevents reuse after deleting rows. History uses the primary-key index to select the first 100 records after the cursor in ascending order. There is no automatic history deletion.

WAL mode and `synchronous=FULL` commit each insertion before broadcasting. Blocking database operations run on Tokio's blocking pool, with a shared lock preserving publication and snapshot/subscription ordering. Read/write errors close the affected connection instead of returning misleading history or broadcasting an unsaved block.

For a simple backup, stop the server and copy the entire data directory, including any `-wal`/`-shm` files. Do not copy just the database file while the server is writing; use SQLite's backup API for live backups. A new database selects a separate client cache. Restoring an older backup retains the database ID and can invalidate client cursors; rollback recovery is not implemented.

A bounded broadcast queue allows independent clients to receive without waiting for a slow client. A lagging receiver is disconnected rather than silently skipping records. Ctrl+C closes the listener and active connections.

The server still observes network connections, IP addresses, publication times, and sizes. It provides neither transport anonymity nor authentication. Disk history is currently unbounded; provision storage accordingly.

## Checks

```sh
cargo fmt --check
cargo test
cargo build
```

Tests cover publication, history replay, cursor filtering, bounded pages, complete catch-up, concurrent publications, empty and exact-page boundaries, exact block preservation, IDs after deletion/reopening, corrupt files, storage errors, and recovery after killing and restarting the actual server process. The Flutter client also contains a cross-language integration test using its own temporary database; see `../client/README.md`.
