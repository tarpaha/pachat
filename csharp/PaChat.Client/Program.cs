using PaChat.Client;

var host     = "127.0.0.1";
var port     = 9000;
string? nickname = null;

for (var i = 0; i < args.Length - 1; i++)
{
    if (args[i] == "--host")     host     = args[i + 1];
    if (args[i] == "--port")     int.TryParse(args[i + 1], out port);
    if (args[i] == "--nickname") nickname = args[i + 1];
}

if (string.IsNullOrWhiteSpace(nickname))
{
    Console.Write("Enter nickname: ");
    nickname = Console.ReadLine()?.Trim() ?? "";
}

if (string.IsNullOrWhiteSpace(nickname))
{
    Console.Error.WriteLine("Nickname cannot be empty.");
    return;
}

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };

using var client = new ChatClient(host, port, nickname);
await client.RunAsync(cts.Token);
