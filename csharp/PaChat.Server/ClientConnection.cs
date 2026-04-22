using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using PaChat.Server.Protocol;

namespace PaChat.Server;

internal sealed class ClientConnection(TcpClient tcpClient, ChatServer server)
{
    public string? Nickname { get; private set; }
    public RSA? ClientRsa { get; private set; }

    private readonly StreamReader _reader = new(tcpClient.GetStream(), Encoding.UTF8, leaveOpen: true);
    private readonly StreamWriter _writer = new(tcpClient.GetStream(), Encoding.UTF8, leaveOpen: true) { AutoFlush = true };

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

            // Import client RSA public key
            try
            {
                var rsa = RSA.Create();
                rsa.ImportSubjectPublicKeyInfo(Convert.FromBase64String(connect.PublicKey), out _);
                ClientRsa = rsa;
            }
            catch
            {
                await SendAsync(new ErrorMessage("INVALID_KEY", "Could not import RSA public key."));
                return;
            }

            // Step 2: send server public key
            await SendAsync(new KeyExchangeMessage(server.ServerPublicKeyBase64));

            // Step 3: register nickname
            if (!server.TryRegisterClient(nick, this))
            {
                await SendAsync(new ErrorMessage("NICKNAME_TAKEN", $"The nickname '{nick}' is already in use."));
                return;
            }
            Nickname = nick;

            // Step 4: send current client list to the new client, then broadcast join
            await SendAsync(new ClientListMessage(server.GetClientNicknames()));
            await server.BroadcastSystemAsync($"{Nickname} has joined the chat.");

            // Step 5: message loop
            while (!ct.IsCancellationRequested)
            {
                line = await _reader.ReadLineAsync(ct);
                if (line is null) break;

                BaseMessage? msg;
                try { msg = ProtocolSerializer.Deserialize(line); }
                catch { await SendAsync(new ErrorMessage("PROTOCOL_ERROR", "Malformed JSON.")); continue; }

                if (msg is EncryptedMessage encrypted)
                {
                    string plaintext;
                    try { plaintext = server.Decrypt(encrypted); }
                    catch { await SendAsync(new ErrorMessage("PROTOCOL_ERROR", "Decryption failed.")); continue; }

                    if (plaintext.Length > 2000)
                    {
                        await SendAsync(new ErrorMessage("MESSAGE_TOO_LONG", "Message exceeds 2000 characters."));
                        continue;
                    }

                    await server.BroadcastEncryptedAsync(Nickname, plaintext, exclude: this);
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
                _ = server.BroadcastSystemAsync($"{Nickname} has left the chat.");
            }
            ClientRsa?.Dispose();
            _reader.Dispose();
            _writer.Dispose();
            tcpClient.Dispose();
        }
    }

    public async Task SendAsync(BaseMessage message)
    {
        try
        {
            await _writer.WriteLineAsync(ProtocolSerializer.Serialize(message));
        }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
    }
}
