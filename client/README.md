# PaChat client

Flutter client for an opaque block relay. Supported project targets: Windows and Android.

## Run

From `client/`:

```sh
flutter pub get
flutter run -d windows
```

Start the Rust server separately (see `../server/README.md`). Connect to its host and port; the default is `127.0.0.1:9000`. There is no nickname, registration, or presence list. On Android, use the server machine's reachable address, not the phone's localhost.

## Exchange keys

1. Open the menu → Friends → Created by me → Create friend. Enter the friend's local name.
2. Show and copy that entry's public key. Send it to that friend through another channel.
3. The friend opens Received keys → Import public key and imports your key with a local label.
4. Repeat in the other direction to enable replies.

Every outgoing message is encrypted separately for **all** received public keys, then published as one block. Each created friend has a separate RSA-2048 key pair. RSA-OAEP-SHA256 wraps a fresh AES-256 key for each copy; AES-GCM encrypts the payload with a fresh 12-byte nonce and 16-byte tag. Key generation and message crypto run outside the UI isolate.

Decryption selects the local friend entry and therefore its display name. Possession of a public key permits anyone to encrypt for that entry: this is not cryptographic proof of the sender's identity. There are no signatures in this prototype.

Friends are accessible from the connection screen too. Lists and private keys are stored with `flutter_secure_storage`, separately from host/port preferences. Failed key writes do not update the in-memory friend list. Loading errors are shown rather than silently replacing saved keys. Android automatic backup is disabled for the application.

## Backups

Friends → menu → Encrypted backup. Enter a password of at least 12 characters and save the resulting encrypted text somewhere safe. The backup contains both lists, including private keys. It uses PBKDF2-HMAC-SHA256 (600,000 iterations, random salt) and AES-256-GCM.

Restore backup accepts the saved text and password and merges missing keys, preserving existing entries. The backup does not include chat history. Deleting a created friend removes its private key from the active list; keep a backup if you need to decrypt blocks for that key again.

## Chat behavior

- New blocks arrive only while connected; there is no server history request or automatic retry.
- Undecryptable or malformed encrypted content appears as an unknown message from an unknown source.
- Local history, including unknown blocks and own outgoing messages, survives sessions and is scoped to the configured host and port.
- An outgoing entry starts as `pending`; receipt of the identical block changes it to `stored` with the server ID. This means saved in server memory, not read by a friend.
- Disconnection makes unresolved outgoing entries `unconfirmed`. Identical block bytes are deduplicated using a local SHA-256 digest.
- Server IDs restart after server restart. They are display metadata, not the local deduplication key.
- Maximum plaintext: 16 KiB; maximum recipients: 256. The final encoded publication must also fit in the transport limit, so large recipient lists reduce the usable message size.

This is a test implementation: the server keeps an unbounded in-memory log and client history is rewritten as an encrypted document. There is no history pagination, forward secrecy, metadata anonymity, or multi-device synchronization.

## Checks

```sh
flutter analyze
flutter test
flutter build windows --debug
```

For the real Rust/Flutter integration test, build the server first and pass the executable's absolute path:

```sh
flutter test --dart-define=PACHAT_SERVER_BIN=C:/code/pachat/server/target/debug/pachat-server.exe
```

Without that define, only the real-server test is skipped. Tests cover key persistence, separate recipients, backup recovery, failed writes, framing limits, unknown blocks, echo deduplication, local history, and the friends menu.
