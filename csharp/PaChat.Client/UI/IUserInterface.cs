namespace PaChat.Client.UI;

internal interface IUserInterface : IDisposable
{
    void Initialize();
    void AddMessage(string text, ConsoleColor color);
    void SetClients(IReadOnlyList<string> clients);
    string? ReadLine(CancellationToken ct);
}
