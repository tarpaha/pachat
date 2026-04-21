# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PaChat is a secure, encrypted peer-to-peer chat application. The primary implementation is in C# (.NET 9.0) under `csharp/`. The `flutter/` and `rust/` directories are currently empty placeholders for future ports.

## Build & Run

```bash
# Build everything
dotnet build pachat.sln

# Run the server (defaults: 0.0.0.0:9000)
dotnet run --project csharp/PaChat.Server/PaChat.Server.csproj [--host 0.0.0.0] [--port 9000]

# Run the client (defaults: 127.0.0.1:9000)
dotnet run --project csharp/PaChat.Client/PaChat.Client.csproj [--host 127.0.0.1] [--port 9000] [--nickname alice]
```

There are no tests or linters configured.

## Architecture

### Transport & Protocol

TCP on port 9000. One JSON message per line (LF-terminated). Protocol details in `PROTOCOL.md`.

**Hybrid encryption scheme:**
- RSA-2048-OAEP-SHA256 for AES key transport
- AES-256-GCM for message payload

**Message flow:**
1. Client sends `connect` (nickname + RSA public key)
2. Server replies with `keyexchange` (server's RSA public key)
3. Client sends `message` (AES key encrypted with server's RSA public key, payload encrypted with AES)
4. Server decrypts, re-encrypts for each recipient with their RSA public key, broadcasts as `broadcast`

### Server (`csharp/PaChat.Server/`)

- `ChatServer.cs` — owns the TcpListener, server RSA key pair, and a `ConcurrentDictionary<string, ClientConnection>`. `BroadcastEncryptedAsync` generates a fresh AES key per recipient.
- `ClientConnection.cs` — handles one client's full lifecycle: handshake → registration → receive/broadcast loop → disconnect cleanup.

### Client (`csharp/PaChat.Client/`)

- `ChatClient.cs` — manages the TCP connection, client RSA key pair, and two concurrent async loops: `ReceiveLoopAsync` (render incoming) and `SendLoopAsync` (encrypt and send user input).

### Protocol types (duplicated in both projects)

- `Protocol/MessageTypes.cs` — polymorphic JSON records for all message variants, deserialized via a `type` discriminator field.
- `Protocol/ProtocolSerializer.cs` — thin JSON serialization helpers.

> The `Protocol/` folder is intentionally duplicated in both client and server projects rather than extracted into a shared library.
