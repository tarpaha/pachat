using System.Net.Sockets;
using System.Text;
using PaChat.Protocol;

namespace PaChat.Server;

internal sealed class ClientConnection(TcpClient tcpClient, ChatServer server)
{
    public string? Nickname { get; private set; }

    private readonly StreamReader _reader = new(tcpClient.GetStream(), Encoding.UTF8, leaveOpen: true);
    private readonly StreamWriter _writer = new(tcpClient.GetStream(), new UTF8Encoding(false), leaveOpen: true) { AutoFlush = true };
    private readonly SemaphoreSlim _writeLock = new(1, 1);

    public async Task HandleAsync(CancellationToken ct)
    {
        try
        {
            // Step 1: expect connect message
            var line = await _reader.ReadLineAsync(ct);
            if (line is null) return;

            ConnectMessage connect;
            try
            {
                if (ProtocolSerializer.Deserialize(line) is not ConnectMessage msg)
                {
                    await SendAsync(new ErrorMessage("NOT_AUTHENTICATED", "Expected connect message first."));
                    return;
                }
                connect = msg;
            }
            catch
            {
                await SendAsync(new ErrorMessage("PROTOCOL_ERROR", "Malformed JSON."));
                return;
            }

            // Validate nickname
            var nick = connect.Nickname?.Trim() ?? "";
            if (nick.Length == 0 || nick.Length > 32)
            {
                await SendAsync(new ErrorMessage("NICKNAME_INVALID", "Nickname must be 1–32 characters."));
                return;
            }

            // Register nickname
            if (!server.TryRegisterClient(nick, this))
            {
                await SendAsync(new ErrorMessage("NICKNAME_TAKEN", $"The nickname '{nick}' is already in use."));
                return;
            }
            Nickname = nick;

            // Announce the new peer to all existing clients. They will respond with their own
            // peerhello directly to the newcomer; the server is no longer involved in key exchange.
            await server.BroadcastAsync(new PeerJoinedMessage(nick, connect.Publickey), exclude: this);

            // Message loop — server is a pure relay from here on.
            while (!ct.IsCancellationRequested)
            {
                line = await _reader.ReadLineAsync(ct);
                if (line is null) break;

                BaseMessage? msg;
                try { msg = ProtocolSerializer.Deserialize(line); }
                catch { await SendAsync(new ErrorMessage("PROTOCOL_ERROR", "Malformed JSON.")); continue; }

                switch (msg)
                {
                    case PeerHelloMessage:
                    case ChatMessage:
                        await server.RouteAsync(Nickname, msg);
                        break;
                    default:
                        await SendAsync(new ErrorMessage("PROTOCOL_ERROR", "Unexpected message type."));
                        break;
                }
            }
        }
        catch (OperationCanceledException) { }
        catch (IOException) { }
        finally
        {
            if (Nickname is not null)
            {
                server.UnregisterClient(Nickname);
                _ = server.BroadcastAsync(new PeerLeftMessage(Nickname));
            }
            _reader.Dispose();
            _writer.Dispose();
            tcpClient.Dispose();
            _writeLock.Dispose();
        }
    }

    public async Task SendAsync(BaseMessage message)
    {
        var line = ProtocolSerializer.Serialize(message);
        try
        {
            await _writeLock.WaitAsync();
        }
        catch (ObjectDisposedException) { return; }

        try
        {
            await _writer.WriteLineAsync(line);
        }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
        finally
        {
            try { _writeLock.Release(); }
            catch (ObjectDisposedException) { }
        }
    }
}
