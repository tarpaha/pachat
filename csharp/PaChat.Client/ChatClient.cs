using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using PaChat.Client.Protocol;
using PaChat.Client.UI;

namespace PaChat.Client;

internal sealed class ChatClient(string host, int port, string nickname) : IDisposable
{
    private readonly RSA _clientRsa = RSA.Create(2048);
    private readonly ConsoleUI _ui = new();
    private readonly List<string> _onlineClients = [];
    private RSA? _serverRsa;

    public async Task RunAsync(CancellationToken ct)
    {
        using var tcpClient = new TcpClient();
        try
        {
            await tcpClient.ConnectAsync(host, port, ct);
        }
        catch (SocketException)
        {
            Console.Error.WriteLine($"Cannot connect to server at {host}:{port}. Is the server running?");
            return;
        }
        tcpClient.NoDelay = true;

        var stream = tcpClient.GetStream();
        using var reader = new StreamReader(stream, Encoding.UTF8, leaveOpen: true);
        using var writer = new StreamWriter(stream, Encoding.UTF8, leaveOpen: true) { AutoFlush = true };

        var pubKey = Convert.ToBase64String(_clientRsa.ExportSubjectPublicKeyInfo());
        await writer.WriteLineAsync(ProtocolSerializer.Serialize(new ConnectMessage(nickname, pubKey)));

        var line = await reader.ReadLineAsync(ct);
        if (line is null) { Console.Error.WriteLine("Server closed connection."); return; }

        if (ProtocolSerializer.Deserialize(line) is KeyExchangeMessage kex)
        {
            _serverRsa = RSA.Create();
            _serverRsa.ImportSubjectPublicKeyInfo(Convert.FromBase64String(kex.ServerPublicKey), out _);
        }
        else
        {
            // Error before keyexchange (e.g. NICKNAME_TAKEN) — UI not yet active
            PrintPreUiMessage(ProtocolSerializer.Deserialize(line));
            return;
        }

        _ui.Initialize();
        _ui.AddMessage($"connected as [{nickname}] — ctrl+c to quit", ConsoleColor.DarkGray);

        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(ct);

        var receiveTask = ReceiveLoopAsync(reader, linkedCts.Token);
        var sendTask    = SendLoopAsync(writer, linkedCts.Token);

        await Task.WhenAny(receiveTask, sendTask);
        await linkedCts.CancelAsync();

        try { await Task.WhenAll(receiveTask, sendTask); }
        catch (OperationCanceledException) { }

        _ui.AddMessage("disconnected.", ConsoleColor.DarkGray);
        await Task.Delay(800, CancellationToken.None); // let the user read the message
    }

    private async Task ReceiveLoopAsync(StreamReader reader, CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested)
            {
                var line = await reader.ReadLineAsync(ct);
                if (line is null) break;

                try { HandleMessage(ProtocolSerializer.Deserialize(line)); }
                catch { }
            }
        }
        catch (OperationCanceledException) { }
        catch (IOException) { }
    }

    private async Task SendLoopAsync(StreamWriter writer, CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested)
            {
                var text = await Task.Run(() => _ui.ReadLine(ct), ct);
                if (text is null) break;
                if (string.IsNullOrWhiteSpace(text)) continue;

                var msg = Encrypt(text);
                await writer.WriteLineAsync(ProtocolSerializer.Serialize(msg));

                var time = DateTime.Now.ToString("HH:mm");
                _ui.AddMessage($"[{time}] <{nickname}> {text}", ConsoleColor.DarkCyan);
            }
        }
        catch (OperationCanceledException) { }
        catch (IOException) { }
    }

    private void HandleMessage(BaseMessage? msg)
    {
        if (msg is null) return;

        switch (msg)
        {
            case BroadcastMessage bcast:
                var text = Decrypt(bcast);
                var time = DateTime.Parse(bcast.Timestamp).ToLocalTime().ToString("HH:mm");
                _ui.AddMessage($"[{time}] <{bcast.Nickname}> {text}", ConsoleColor.White);
                break;

            case ClientListMessage clientList:
                _onlineClients.Clear();
                _onlineClients.AddRange(clientList.Nicknames);
                _ui.SetClients(_onlineClients);
                break;

            case SystemMessage sys:
                _ui.AddMessage($"*** {sys.Text}", ConsoleColor.Yellow);
                UpdateClientList(sys.Text);
                break;

            case ErrorMessage err:
                _ui.AddMessage($"error {err.Code}: {err.Text}", ConsoleColor.Red);
                break;
        }
    }

    private void UpdateClientList(string text)
    {
        const string joined = " has joined the chat.";
        const string left   = " has left the chat.";

        if (text.EndsWith(joined))
        {
            var nick = text[..^joined.Length];
            if (!_onlineClients.Contains(nick, StringComparer.OrdinalIgnoreCase))
                _onlineClients.Add(nick);
        }
        else if (text.EndsWith(left))
        {
            var nick = text[..^left.Length];
            _onlineClients.RemoveAll(n => string.Equals(n, nick, StringComparison.OrdinalIgnoreCase));
        }

        _ui.SetClients(_onlineClients);
    }

    private EncryptedMessage Encrypt(string text)
    {
        var plaintextBytes = Encoding.UTF8.GetBytes(text);
        var aesKey    = RandomNumberGenerator.GetBytes(32);
        var iv        = RandomNumberGenerator.GetBytes(12);
        var ciphertext = new byte[plaintextBytes.Length];
        var tag       = new byte[16];

        using var aesGcm = new AesGcm(aesKey, 16);
        aesGcm.Encrypt(iv, plaintextBytes, ciphertext, tag);

        var encryptedKey = _serverRsa!.Encrypt(aesKey, RSAEncryptionPadding.OaepSHA256);

        return new EncryptedMessage(
            Convert.ToBase64String(encryptedKey),
            Convert.ToBase64String(iv),
            Convert.ToBase64String(ciphertext),
            Convert.ToBase64String(tag));
    }

    private string Decrypt(BroadcastMessage msg)
    {
        var aesKey    = _clientRsa.Decrypt(Convert.FromBase64String(msg.EncryptedKey), RSAEncryptionPadding.OaepSHA256);
        var iv        = Convert.FromBase64String(msg.Iv);
        var ciphertext = Convert.FromBase64String(msg.Ciphertext);
        var tag       = Convert.FromBase64String(msg.Tag);
        var plaintext = new byte[ciphertext.Length];

        using var aesGcm = new AesGcm(aesKey, 16);
        aesGcm.Decrypt(iv, ciphertext, tag, plaintext);
        return Encoding.UTF8.GetString(plaintext);
    }

    private static void PrintPreUiMessage(BaseMessage? msg)
    {
        if (msg is ErrorMessage err)
            Console.Error.WriteLine($"error {err.Code}: {err.Text}");
    }

    public void Dispose()
    {
        _clientRsa.Dispose();
        _serverRsa?.Dispose();
        _ui.Dispose();
    }
}
