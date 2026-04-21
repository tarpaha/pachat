using PaChat.Server;

var host = "0.0.0.0";
var port = 9000;

for (var i = 0; i < args.Length - 1; i++)
{
    if (args[i] == "--host") host = args[i + 1];
    if (args[i] == "--port") int.TryParse(args[i + 1], out port);
}

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };
AppDomain.CurrentDomain.ProcessExit += (_, _) => { try { cts.Cancel(); } catch (ObjectDisposedException) { } };

using var server = new ChatServer(host, port);
await server.RunAsync(cts.Token);
