# PaChat

Secure peer-to-peer chat. The server is a blind relay — it never sees message contents.

## Run

**Server** (defaults: 0.0.0.0:9000):
```bash
dotnet run --project csharp/PaChat.Server/PaChat.Server.csproj
```

**Client** (defaults: 127.0.0.1:9000, prompts for nickname if not provided):
```bash
dotnet run --project csharp/PaChat.Client/PaChat.Client.csproj -- --nickname alice
dotnet run --project csharp/PaChat.Client/PaChat.Client.csproj -- --nickname bob
```

Custom host/port:
```bash
dotnet run --project csharp/PaChat.Server/PaChat.Server.csproj -- --host 0.0.0.0 --port 9000
dotnet run --project csharp/PaChat.Client/PaChat.Client.csproj -- --host 192.168.1.10 --port 9000 --nickname alice
```

## Build

```bash
dotnet build csharp/pachat.sln
```

## Protocol

See [PROTOCOL.md](PROTOCOL.md) for the wire format specification.
