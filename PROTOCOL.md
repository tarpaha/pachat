# pahachat Protocol v1

## Transport

TCP, port 9000 (default). Each message is a single JSON object on one line terminated by `\n` (LF). No CR, no pretty-printing.

## Security

Hybrid encryption: RSA-2048-OAEP-SHA256 for key transport, AES-256-GCM for message confidentiality.

- Client generates RSA-2048 key pair on startup. Public key sent to server in `connect`.
- Server generates one RSA-2048 key pair on startup. Public key sent to client in `keyexchange`.
- `message` (C→S): client encrypts with server's RSA public key + AES-GCM.
- `broadcast` (S→C): server re-encrypts for each recipient using their RSA public key.
- `system` and `error` are plaintext (originated by server).

Public keys are DER-encoded SubjectPublicKeyInfo (SPKI), base64-encoded.
Encrypted fields (`encryptedKey`, `iv`, `ciphertext`, `tag`) are base64-encoded bytes.

## Message Types

### `connect` (C→S)
Sent exactly once, immediately after TCP connection.
```json
{"type":"connect","nickname":"alice","publicKey":"<base64 DER SPKI>"}
```
- `nickname`: 1–32 chars, no leading/trailing whitespace.
- `publicKey`: RSA-2048 public key, DER SPKI, base64.

### `keyexchange` (S→C)
Sent only to the connecting client, before any broadcast.
```json
{"type":"keyexchange","serverPublicKey":"<base64 DER SPKI>"}
```

### `message` (C→S)
```json
{"type":"message","encryptedKey":"<base64>","iv":"<base64>","ciphertext":"<base64>","tag":"<base64>"}
```
- `encryptedKey`: AES-256 key encrypted with server's RSA public key (OAEP-SHA256).
- `iv`: 12-byte GCM nonce.
- `ciphertext`: AES-256-GCM encrypted plaintext.
- `tag`: 16-byte GCM authentication tag.

### `broadcast` (S→C)
Sent to every connected client. Each `broadcast` is individually encrypted for its recipient.
```json
{"type":"broadcast","nickname":"alice","timestamp":"2026-04-20T14:32:00Z","encryptedKey":"<base64>","iv":"<base64>","ciphertext":"<base64>","tag":"<base64>"}
```
- `timestamp`: ISO 8601 UTC, assigned by server.
- Encryption same as `message` but using recipient's RSA public key.

### `system` (S→C)
```json
{"type":"system","text":"alice has joined the chat","timestamp":"2026-04-20T14:32:00Z"}
```

### `error` (S→C)
```json
{"type":"error","code":"NICKNAME_TAKEN","text":"The nickname 'alice' is already in use"}
```

**Error codes:** `NICKNAME_TAKEN`, `NICKNAME_INVALID`, `NOT_AUTHENTICATED`, `MESSAGE_TOO_LONG`, `INVALID_KEY`, `PROTOCOL_ERROR`

## Connection Lifecycle

```
CLIENT                          SERVER
  |--- TCP connect -------------->|
  |--- {"type":"connect",...} --->|
  |<-- {"type":"keyexchange",...}-|
  |<-- {"type":"system",...} -----|  (broadcast: "alice joined")
  |                               |
  |--- {"type":"message",...} --->|
  |<-- {"type":"broadcast",...} --| (one per connected client, individually encrypted)
  |                               |
  |--- TCP close ---------------->|
  |<-- {"type":"system",...} -----|  (broadcast: "alice left")
```
