using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using PaChat.Protocol;

namespace PaChat.Server;

internal sealed class ChatServer
{
    private readonly TcpListener _listener;
    private readonly ConcurrentDictionary<string, ClientConnection> _clients = new(StringComparer.OrdinalIgnoreCase);

    public ChatServer(string host, int port)
    {
        _listener = new TcpListener(IPAddress.Parse(host), port);
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

    public async Task BroadcastAsync(BaseMessage msg, ClientConnection? exclude = null)
    {
        foreach (var (_, client) in _clients.ToArray())
        {
            if (client == exclude) continue;
            await client.SendAsync(msg);
        }
    }

    public async Task RouteAsync(string senderNick, BaseMessage msg)
    {
        var (to, outgoing) = msg switch
        {
            PeerHelloMessage h => (h.To, (BaseMessage)(h with { To = null, From = senderNick })),
            ChatMessage      c => (c.To, (BaseMessage)(c with { To = null, From = senderNick })),
            _ => (null, null!)
        };

        if (to is null) return;
        if (!_clients.TryGetValue(to, out var target)) return;

        await target.SendAsync(outgoing);
    }
}
