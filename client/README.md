# PaChat client

Flutter client for an opaque block relay. Project targets: Windows and Android.

## Run and select a profile

From `client/`:

```sh
flutter pub get
flutter run -d windows
```

The first screen lists local profiles. Enter `Alice` and choose **Create / open profile**. Open another application window and choose `Bob`. Each profile has its own friends, keys, server settings and history. Select the same profile on the next launch to recover its saved friends. Names are case-insensitive. Use Back from the connection screen to switch profiles.

Only one window can use a given profile at a time. A held file lock is released on closing the profile or exiting the process. Different profiles can run concurrently against the same server. Profiles are local organizational identities, not password-protected accounts; processes running as the same OS user can access their storage.

Start the Rust server separately (see `../server/README.md`). Default connection: `127.0.0.1:9000`. Profiles and their names are never sent to the server. There is no registration or presence list. On Android, use the server machine's reachable address, not the phone's localhost.

## Exchange keys

1. Open the menu → Friends → Created by me → Create friend. Enter the friend's local name.
2. Show and copy that entry's public key. Send it to that friend through another channel.
3. The friend opens Received keys → Import public key in their own profile and imports your key with a local label.
4. Repeat in the other direction to enable replies.

Every outgoing message is encrypted separately for **all** received public keys and the profile's own public key, then published as one block. Each created friend has a separate RSA-2048 key pair. RSA-OAEP-SHA256 wraps a fresh AES-256 key for each copy; AES-GCM encrypts the payload with a fresh 12-byte nonce and 16-byte tag. Key generation and message crypto run outside the UI isolate.

Decryption selects the local friend entry and therefore its display name. Possession of a public key permits anyone to encrypt for that entry: this is not cryptographic proof of the sender's identity. There are no signatures in this prototype.

## Local storage

Profiles live under the platform application-support directory, in `profiles/<hash-of-name>/`.

- Windows: each profile's friends and RSA private keys are protected with Windows DPAPI in `friends.dpapi`. The old plugin's shared `flutter_secure_storage.dat` file is not used. Writes go to a temporary file, are flushed, and then renamed into place. Failed decryption does not delete the file.
- Android: `flutter_secure_storage` uses a separate storage namespace for each profile, backed by Android key protection. Automatic Android backup is disabled.
- Settings and received history are separate files inside the profile folder. History also distinguishes the configured server host and port.
- History format: `{"version":2,"blocks":[{"id":1,"block":"..."}]}`. It contains only original server IDs and encrypted block strings, with no cached plaintext, friend identity or timestamp.
- Incoming text is decrypted again with the selected profile's keys when loading history or changing friends. Decoded text exists only in memory.
- Failed history writes show a warning and a **Retry saving history** button. The TCP connection stays open and blocks stay in memory. Subsequent saves retry the full received history. Closing the window before a successful retry can lose unsaved blocks.

Old shared storage is left untouched and is not automatically imported into a named profile. To keep friends from an older installation, export an encrypted friends backup there and restore it into the intended profile. Old plaintext history is not imported.

## Backups

Friends → menu → Encrypted backup. Enter a password of at least 12 characters and save the encrypted text somewhere safe. The backup contains both friend lists and the profile's own key pairs, including private keys. It uses PBKDF2-HMAC-SHA256 (600,000 iterations, random salt) and AES-256-GCM.

Restore backup merges missing keys into the current profile, preserving existing entries. Restored own keys remain available for reading old messages; the current own key continues to be used for new self copies. Backups do not include history. Without a matching private key, a saved block displays as unknown; restoring the key makes matching blocks readable again.

## Chat behavior

- New blocks arrive only while connected; there is no server history request or automatic resend.
- Only blocks received in `new_block` are added to history. There is no separate outgoing history or outgoing status.
- The profile generates and securely saves an own RSA pair once. Existing profiles gain this pair on first opening after the update. Its public key is not exposed in the friends UI or sent to the server. Each publication includes a copy encrypted for this key. When the block returns, own keys are tried first; successful decryption displays You on the right. This also works after restarting or restoring the profile backup. Older blocks without a self copy cannot be recovered this way.
- Unknown or malformed encrypted content never exposes message text.
- Server IDs restart after server restart; they are not treated as globally unique.
- Maximum plaintext: 16 KiB; maximum 256 friend copies plus one self copy. Sending without imported friends is allowed and creates only the self copy.

This is a test implementation: the server keeps an unbounded in-memory log and client history rewrites its block list. There is no history pagination, forward secrecy, metadata anonymity, or multi-device synchronization.

## Checks

```sh
flutter analyze
flutter test
flutter build windows --release
```

For the real Rust/Flutter integration test, build the server and pass the executable's absolute path:

```sh
flutter test --dart-define=PACHAT_SERVER_BIN=C:/code/pachat/server/target/debug/pachat-server.exe
```

Without that define the real-server test is skipped. Windows profile tests exercise actual DPAPI files, persistence, profile exclusion and preservation of corrupt files. Network tests cover encrypted exchange, raw-only history, reopening with and without matching keys, and a failed history write without disconnection.
