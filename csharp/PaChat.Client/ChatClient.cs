using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using PaChat.Client.Protocol;

namespace PaChat.Client;

internal sealed class ChatClient(string host, int port, string nickname) : IDisposable
{
    private readonly RSA _clientRsa = RSA.Create(2048);
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

        // Send connect with our public key
        var pubKey = Convert.ToBase64String(_clientRsa.ExportSubjectPublicKeyInfo());
        await writer.WriteLineAsync(ProtocolSerializer.Serialize(new ConnectMessage(nickname, pubKey)));

        // Expect keyexchange before doing anything else
        var line = await reader.ReadLineAsync(ct);
        if (line is null) { Console.WriteLine("Server closed connection."); return; }

        if (ProtocolSerializer.Deserialize(line) is KeyExchangeMessage kex)
        {
            _serverRsa = RSA.Create();
            _serverRsa.ImportSubjectPublicKeyInfo(Convert.FromBase64String(kex.ServerPublicKey), out _);
        }
        else
        {
            // Could be an error (e.g. NICKNAME_TAKEN) before keyexchange
            RenderMessage(ProtocolSerializer.Deserialize(line));
            return;
        }

        Console.WriteLine($"Connected as [{nickname}]. Type messages and press Enter. Ctrl+C to quit.\n");

        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(ct);

        var receiveTask = ReceiveLoopAsync(reader, linkedCts.Token);
        var sendTask    = SendLoopAsync(writer, linkedCts.Token);

        await Task.WhenAny(receiveTask, sendTask);
        await linkedCts.CancelAsync();

        // Drain the other task
        try { await Task.WhenAll(receiveTask, sendTask); }
        catch (OperationCanceledException) { }

        Console.WriteLine("\nDisconnected.");
    }

    private async Task ReceiveLoopAsync(StreamReader reader, CancellationToken ct)
    {
        try
        {
            while (!ct.IsCancellationRequested)
            {
                var line = await reader.ReadLineAsync(ct);
                if (line is null) break;

                try { RenderMessage(ProtocolSerializer.Deserialize(line)); }
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
                var text = await Task.Run(() => Console.ReadLine(), ct);
                if (text is null) break;
                if (string.IsNullOrWhiteSpace(text)) continue;

                var msg = Encrypt(text);
                await writer.WriteLineAsync(ProtocolSerializer.Serialize(msg));
            }
        }
        catch (OperationCanceledException) { }
        catch (IOException) { }
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

    private void RenderMessage(BaseMessage? msg)
    {
        if (msg is null) return;

        var prev = Console.ForegroundColor;
        switch (msg)
        {
            case BroadcastMessage bcast:
                var text = Decrypt(bcast);
                var time = DateTime.Parse(bcast.Timestamp).ToLocalTime().ToString("HH:mm");
                Console.ForegroundColor = bcast.Nickname == nickname ? ConsoleColor.DarkCyan : ConsoleColor.White;
                Console.WriteLine($"[{time}] <{bcast.Nickname}> {text}");
                break;

            case SystemMessage sys:
                Console.ForegroundColor = ConsoleColor.Yellow;
                Console.WriteLine($"*** {sys.Text}");
                break;

            case ErrorMessage err:
                Console.ForegroundColor = ConsoleColor.Red;
                Console.WriteLine($"ERROR {err.Code}: {err.Text}");
                break;
        }
        Console.ForegroundColor = prev;
    }

    public void Dispose()
    {
        _clientRsa.Dispose();
        _serverRsa?.Dispose();
    }
}
