using System.Collections.Concurrent;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using PaChat.Protocol;
using PaChat.Client.UI;

namespace PaChat.Client;

internal sealed class ChatClient(string host, int port, string nickname, IUserInterface ui) : IDisposable
{
    private readonly RSA _clientRsa = RSA.Create(2048);
    private readonly ConcurrentDictionary<string, RSA> _peers = new(StringComparer.OrdinalIgnoreCase);
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private string _myPublicKeyBase64 = "";
    private StreamWriter? _writer;

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
        using var writer = new StreamWriter(stream, new UTF8Encoding(false), leaveOpen: true) { AutoFlush = true };
        _writer = writer;

        _myPublicKeyBase64 = Convert.ToBase64String(_clientRsa.ExportSubjectPublicKeyInfo());
        await SendAsync(new ConnectMessage(nickname, _myPublicKeyBase64), ct);

        ui.Initialize();
        ui.AddMessage($"connected as [{nickname}] — ctrl+c to quit", ConsoleColor.DarkGray);
        ui.SetClients(GetRosterForUi());

        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(ct);

        var receiveTask = ReceiveLoopAsync(reader, linkedCts.Token);
        var sendTask    = SendLoopAsync(linkedCts.Token);

        await Task.WhenAny(receiveTask, sendTask);
        await linkedCts.CancelAsync();

        try { await Task.WhenAll(receiveTask, sendTask); }
        catch (OperationCanceledException) { }

        ui.AddMessage("disconnected.", ConsoleColor.DarkGray);
        await Task.Delay(800, CancellationToken.None);
    }

    private async Task ReceiveLoopAsync(StreamReader reader, CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested)
            {
                var line = await reader.ReadLineAsync(ct);
                if (line is null) break;

                BaseMessage? msg;
                try { msg = ProtocolSerializer.Deserialize(line); }
                catch { continue; }

                await HandleMessageAsync(msg, ct);
            }
        }
        catch (OperationCanceledException) { }
        catch (IOException) { }
    }

    private async Task SendLoopAsync(CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested)
            {
                var text = await Task.Run(() => ui.ReadLine(ct), ct);
                if (text is null) break;
                if (string.IsNullOrWhiteSpace(text)) continue;

                var ts = DateTime.UtcNow.ToString("O");
                var plaintextBytes = Encoding.UTF8.GetBytes(text);

                foreach (var (peerNick, peerKey) in _peers.ToArray())
                {
                    var msg = EncryptForPeer(peerNick, peerKey, plaintextBytes, ts);
                    await SendAsync(msg, ct);
                }

                var time = DateTime.Parse(ts).ToLocalTime().ToString("HH:mm");
                ui.AddMessage($"[{time}] <{nickname}> {text}", ConsoleColor.DarkCyan);
            }
        }
        catch (OperationCanceledException) { }
        catch (IOException) { }
    }

    private async Task HandleMessageAsync(BaseMessage? msg, CancellationToken ct)
    {
        switch (msg)
        {
            case PeerJoinedMessage joined:
                if (AddPeer(joined.Nickname, joined.Publickey))
                    ui.AddMessage($"*** {joined.Nickname} joined", ConsoleColor.Yellow);
                // Reply with our own peerhello so the newcomer learns about us.
                await SendAsync(new PeerHelloMessage(
                    To:        joined.Nickname,
                    From:      null,
                    Nickname:  nickname,
                    Publickey: _myPublicKeyBase64), ct);
                break;

            case PeerHelloMessage hello:
                if (AddPeer(hello.Nickname, hello.Publickey))
                    ui.AddMessage($"*** {hello.Nickname} joined", ConsoleColor.Yellow);
                break;

            case PeerLeftMessage left:
                if (_peers.TryRemove(left.Nickname, out var rsa))
                {
                    rsa.Dispose();
                    ui.SetClients(GetRosterForUi());
                    ui.AddMessage($"*** {left.Nickname} left", ConsoleColor.Yellow);
                }
                break;

            case ChatMessage chat:
                if (chat.From is null) break;
                string text;
                try { text = Decrypt(chat); }
                catch { break; }
                var time = DateTime.Parse(chat.Timestamp).ToLocalTime().ToString("HH:mm");
                ui.AddMessage($"[{time}] <{chat.From}> {text}", ConsoleColor.White);
                break;

            case ErrorMessage err:
                ui.AddMessage($"error {err.Code}: {err.Text}", ConsoleColor.Red);
                break;
        }
    }

    private bool AddPeer(string nick, string publicKeyBase64)
    {
        RSA rsa;
        try
        {
            rsa = RSA.Create();
            rsa.ImportSubjectPublicKeyInfo(Convert.FromBase64String(publicKeyBase64), out _);
        }
        catch
        {
            return false;
        }

        if (_peers.TryAdd(nick, rsa))
        {
            ui.SetClients(GetRosterForUi());
            return true;
        }

        rsa.Dispose();
        return false;
    }

    private List<string> GetRosterForUi()
    {
        var list = _peers.Keys.ToList();
        list.Add(nickname);
        list.Sort(StringComparer.OrdinalIgnoreCase);
        return list;
    }

    private async Task SendAsync(BaseMessage msg, CancellationToken ct)
    {
        if (_writer is null) return;
        var line = ProtocolSerializer.Serialize(msg);

        try { await _writeLock.WaitAsync(ct); }
        catch (OperationCanceledException) { return; }
        catch (ObjectDisposedException) { return; }

        try
        {
            await _writer.WriteLineAsync(line.AsMemory(), ct);
        }
        catch (OperationCanceledException) { }
        catch (IOException) { }
        catch (ObjectDisposedException) { }
        finally
        {
            try { _writeLock.Release(); }
            catch (ObjectDisposedException) { }
        }
    }

    private static ChatMessage EncryptForPeer(string peerNick, RSA peerKey, byte[] plaintext, string timestamp)
    {
        var aesKey     = RandomNumberGenerator.GetBytes(32);
        var iv         = RandomNumberGenerator.GetBytes(12);
        var ciphertext = new byte[plaintext.Length];
        var tag        = new byte[16];

        using var aesGcm = new AesGcm(aesKey, 16);
        aesGcm.Encrypt(iv, plaintext, ciphertext, tag);

        var encryptedKey = peerKey.Encrypt(aesKey, RSAEncryptionPadding.OaepSHA256);

        return new ChatMessage(
            To:           peerNick,
            From:         null,
            Timestamp:    timestamp,
            Encryptedkey: Convert.ToBase64String(encryptedKey),
            Iv:           Convert.ToBase64String(iv),
            Ciphertext:   Convert.ToBase64String(ciphertext),
            Tag:          Convert.ToBase64String(tag));
    }

    private string Decrypt(ChatMessage msg)
    {
        var aesKey     = _clientRsa.Decrypt(Convert.FromBase64String(msg.Encryptedkey), RSAEncryptionPadding.OaepSHA256);
        var iv         = Convert.FromBase64String(msg.Iv);
        var ciphertext = Convert.FromBase64String(msg.Ciphertext);
        var tag        = Convert.FromBase64String(msg.Tag);
        var plaintext  = new byte[ciphertext.Length];

        using var aesGcm = new AesGcm(aesKey, 16);
        aesGcm.Decrypt(iv, ciphertext, tag, plaintext);
        return Encoding.UTF8.GetString(plaintext);
    }

    public void Dispose()
    {
        _clientRsa.Dispose();
        foreach (var (_, rsa) in _peers)
            rsa.Dispose();
        _peers.Clear();
        _writeLock.Dispose();
    }
}
