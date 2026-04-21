using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using PaChat.Server.Protocol;

namespace PaChat.Server;

internal sealed class ChatServer : IDisposable
{
    private readonly TcpListener _listener;
    private readonly RSA _serverRsa = RSA.Create(2048);
    private readonly ConcurrentDictionary<string, ClientConnection> _clients = new(StringComparer.OrdinalIgnoreCase);

    public string ServerPublicKeyBase64 { get; }

    public ChatServer(string host, int port)
    {
        _listener = new TcpListener(IPAddress.Parse(host), port);
        ServerPublicKeyBase64 = Convert.ToBase64String(_serverRsa.ExportSubjectPublicKeyInfo());
    }

    public async Task RunAsync(CancellationToken ct)
    {
        _listener.Start();
        Console.WriteLine($"Server listening on {_listener.LocalEndpoint}");

        var clientTasks = new List<Task>();
        try
        {
            while (!ct.IsCancellationRequested)
            {
                var tcpClient = await _listener.AcceptTcpClientAsync(ct);
                tcpClient.NoDelay = true;
                var conn = new ClientConnection(tcpClient, this);
                clientTasks.Add(conn.HandleAsync(ct));
            }
        }
        catch (OperationCanceledException) { }
        finally
        {
            _listener.Stop();
            await Task.WhenAll(clientTasks);
        }
    }

    public bool TryRegisterClient(string nickname, ClientConnection conn)
        => _clients.TryAdd(nickname, conn);

    public void UnregisterClient(string nickname)
        => _clients.TryRemove(nickname, out _);

    // Decrypt message sent by a client (AES key encrypted with server's RSA public key)
    public string Decrypt(EncryptedMessage msg)
    {
        var aesKey    = _serverRsa.Decrypt(Convert.FromBase64String(msg.EncryptedKey), RSAEncryptionPadding.OaepSHA256);
        var iv        = Convert.FromBase64String(msg.Iv);
        var ciphertext = Convert.FromBase64String(msg.Ciphertext);
        var tag       = Convert.FromBase64String(msg.Tag);
        var plaintext = new byte[ciphertext.Length];

        using var aesGcm = new AesGcm(aesKey, 16);
        aesGcm.Decrypt(iv, ciphertext, tag, plaintext);
        return Encoding.UTF8.GetString(plaintext);
    }

    public async Task BroadcastEncryptedAsync(string senderNickname, string plaintext, ClientConnection? exclude = null)
    {
        var timestamp = DateTime.UtcNow.ToString("O");
        var plaintextBytes = Encoding.UTF8.GetBytes(plaintext);

        foreach (var (_, client) in _clients.ToArray())
        {
            if (client == exclude) continue;
            if (client.ClientRsa is null) continue;

            var aesKey    = RandomNumberGenerator.GetBytes(32);
            var iv        = RandomNumberGenerator.GetBytes(12);
            var ciphertext = new byte[plaintextBytes.Length];
            var tag       = new byte[16];

            using var aesGcm = new AesGcm(aesKey, 16);
            aesGcm.Encrypt(iv, plaintextBytes, ciphertext, tag);

            var encryptedKey = client.ClientRsa.Encrypt(aesKey, RSAEncryptionPadding.OaepSHA256);

            await client.SendAsync(new BroadcastMessage(
                senderNickname,
                timestamp,
                Convert.ToBase64String(encryptedKey),
                Convert.ToBase64String(iv),
                Convert.ToBase64String(ciphertext),
                Convert.ToBase64String(tag)));
        }
    }

    public async Task BroadcastSystemAsync(string text)
    {
        var msg = new SystemMessage(text, DateTime.UtcNow.ToString("O"));
        foreach (var (_, client) in _clients.ToArray())
            await client.SendAsync(msg);
    }

    public void Dispose() => _serverRsa.Dispose();
}
