# pahachat Protocol v2

## Transport

TCP, port 9000 (default). Each message is a single JSON object on one line terminated by `\n` (LF). No CR, no pretty-printing.

## Security model

End-to-end: the server never sees plaintext message bodies. The server's only role is routing
JSON envelopes by nickname. All confidentiality is between peers.

- Each client generates an RSA-2048 key pair on startup. The private key never leaves the client.
- On `connect`, the client publishes its nickname and public key. The server forwards them to all
  other connected clients in a `peerjoined` broadcast.
- Existing clients respond to a `peerjoined` by sending a directed `peerhello` to the newcomer
  carrying their own (nickname, publickey). After this, every client has every other client's
  public key in its local roster.
- Chat messages are encrypted **per recipient**: the sender produces one `chat` envelope per peer,
  each addressed (`to`) to a specific nickname and encrypted under that peer's RSA public key.
- The server reads only the `to` field, looks up the corresponding socket, stamps `from` with
  the sender's nickname, and forwards the envelope unchanged.

Hybrid encryption per envelope (unchanged from v1, but now keyed per peer):
- RSA-2048-OAEP-SHA256 wraps a fresh AES-256 key.
- AES-256-GCM encrypts the payload (12-byte nonce, 16-byte tag).

Public keys are DER-encoded SubjectPublicKeyInfo (SPKI), base64-encoded. Encrypted fields
(`encryptedkey`, `iv`, `ciphertext`, `tag`) are base64-encoded bytes.

## Message Types

### `connect` (C→S)
Sent exactly once, immediately after TCP connection.
```json
{"type":"connect","nickname":"alice","publickey":"<base64 DER SPKI>"}
```
- `nickname`: 1–32 chars, no leading/trailing whitespace.
- `publickey`: client's RSA-2048 public key, DER SPKI, base64.

### `peerjoined` (S→C)
Server broadcast when a new client successfully registers. Sent to every other connected client.
```json
{"type":"peerjoined","nickname":"alice","publickey":"<base64 DER SPKI>"}
```

### `peerleft` (S→C)
Server broadcast when a client disconnects.
```json
{"type":"peerleft","nickname":"alice"}
```

### `peerhello` (C→S, S→C)
Directed key announcement, sent by an existing peer in response to a `peerjoined`.
- Client→server form (sent by the announcer):
  ```json
  {"type":"peerhello","to":"alice","nickname":"bob","publickey":"<base64 DER SPKI>"}
  ```
- Server→client form (delivered to the addressee):
  ```json
  {"type":"peerhello","from":"bob","nickname":"bob","publickey":"<base64 DER SPKI>"}
  ```
The server replaces `to` with `from` (= the sending client's registered nickname) before forwarding.
A receiver can verify `from == nickname` and reject otherwise.

### `chat` (C→S, S→C)
End-to-end encrypted chat envelope, sent by the author once per intended recipient.
- Client→server form:
  ```json
  {"type":"chat","to":"bob","timestamp":"2026-05-10T14:32:00.0000000Z",
   "encryptedkey":"<base64>","iv":"<base64>","ciphertext":"<base64>","tag":"<base64>"}
  ```
- Server→client form (delivered to the addressee):
  ```json
  {"type":"chat","from":"alice","timestamp":"2026-05-10T14:32:00.0000000Z",
   "encryptedkey":"<base64>","iv":"<base64>","ciphertext":"<base64>","tag":"<base64>"}
  ```
- `timestamp`: ISO 8601 UTC, set by the **sender** (the server is no longer a time authority).
- `encryptedkey`: AES-256 key encrypted with the recipient's RSA public key (OAEP-SHA256).
- `iv`: 12-byte GCM nonce.
- `ciphertext`: AES-256-GCM encrypted UTF-8 plaintext.
- `tag`: 16-byte GCM authentication tag.

### `error` (S→C)
```json
{"type":"error","code":"NICKNAME_TAKEN","text":"The nickname 'alice' is already in use"}
```

**Error codes:** `NICKNAME_TAKEN`, `NICKNAME_INVALID`, `NOT_AUTHENTICATED`, `PROTOCOL_ERROR`

## Connection Lifecycle

```
NEW CLIENT (alice)        SERVER          EXISTING CLIENTS (bob, carol)
  |---TCP connect---------->|
  |---{"type":"connect"}--->|
  |                         |---{"type":"peerjoined",alice,pk}--->|  (to bob, carol)
  |<--{"type":"peerhello",from:bob,bob,pk}------------------------|
  |<--{"type":"peerhello",from:carol,carol,pk}--------------------|
  |
  | alice writes "hi":
  |---{"type":"chat",to:bob,...}-->|---{"type":"chat",from:alice,...}-->| bob
  |---{"type":"chat",to:carol,...}->|---{"type":"chat",from:alice,...}-->| carol
  |
  |---TCP close ----------->|
  |                         |---{"type":"peerleft",alice}--------->|  (to bob, carol)
```

The server maintains only `nickname → socket`. Public keys are seen briefly during
`peerjoined` rebroadcasting; no key material is persisted server-side.

## Handshake notes

- The newcomer does not receive an explicit roster from the server; the roster is assembled
  from the stream of incoming `peerhello` replies.
- If no other clients are connected, the newcomer simply waits — its roster stays empty
  until someone joins.
- `peerhello` from a peer arriving before that peer's `peerjoined` is unexpected; in practice
  the server-broadcast `peerjoined` always precedes any `peerhello` reply originating from it.
