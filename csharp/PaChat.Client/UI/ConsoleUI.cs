using System.Text;

namespace PaChat.Client.UI;

internal sealed class ConsoleUI : IDisposable
{
    private readonly object _lock = new();
    private readonly List<(string text, ConsoleColor color)> _messages = new();
    private readonly List<string> _clients = new();
    private string _inputBuffer = "";
    private readonly CancellationTokenSource _resizeCts = new();

    private const int PanelWidth = 22; // total width including borders

    public void Initialize()
    {
        Console.OutputEncoding = Encoding.UTF8;
        Console.CursorVisible = false;
        lock (_lock)
            FullRender();
        Task.Run(() => ResizeMonitorLoop(_resizeCts.Token));
    }

    public void AddMessage(string text, ConsoleColor color)
    {
        lock (_lock)
        {
            _messages.Add((text, color));
            RenderMessages();
            RenderClientsPanel();
            PositionCursor();
        }
    }

    public void SetClients(IReadOnlyList<string> clients)
    {
        lock (_lock)
        {
            _clients.Clear();
            _clients.AddRange(clients);
            RenderMessages();
            RenderClientsPanel();
            PositionCursor();
        }
    }

    // Blocks the calling thread; poll ct internally to support cancellation.
    public string? ReadLine(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            if (!Console.KeyAvailable)
            {
                Thread.Sleep(10);
                continue;
            }

            var key = Console.ReadKey(intercept: true);
            lock (_lock)
            {
                switch (key.Key)
                {
                    case ConsoleKey.Enter:
                        var result = _inputBuffer;
                        _inputBuffer = "";
                        RenderInputBar();
                        PositionCursor();
                        return result;

                    case ConsoleKey.Backspace when _inputBuffer.Length > 0:
                        _inputBuffer = _inputBuffer[..^1];
                        break;

                    default:
                        if (!char.IsControl(key.KeyChar))
                            _inputBuffer += key.KeyChar;
                        break;
                }
                RenderInputBar();
                PositionCursor();
            }
        }
        return null;
    }

    public void Dispose()
    {
        _resizeCts.Cancel();
        _resizeCts.Dispose();
        Console.CursorVisible = true;
        Console.ResetColor();
    }

    // ── Resize monitor ────────────────────────────────────────────────────────

    private void ResizeMonitorLoop(CancellationToken ct)
    {
        var (w, h) = (Console.WindowWidth, Console.WindowHeight);
        while (!ct.IsCancellationRequested)
        {
            Thread.Sleep(100);
            var (nw, nh) = (Console.WindowWidth, Console.WindowHeight);
            if (nw == w && nh == h) continue;
            (w, h) = (nw, nh);
            lock (_lock)
                FullRender();
        }
    }

    // ── Rendering ─────────────────────────────────────────────────────────────

    private void FullRender()
    {
        var (w, h) = (Console.WindowWidth, Console.WindowHeight);
        Console.ResetColor();
        for (var r = 0; r < h; r++) { SetPos(0, r); Console.Write(new string(' ', w)); }
        RenderBorder();
        RenderMessages();
        RenderClientsPanel();
        RenderInputBar();
        PositionCursor();
    }

    private void RenderBorder()
    {
        var (w, h) = (Console.WindowWidth, Console.WindowHeight);
        Console.ForegroundColor = ConsoleColor.Blue;
        SetPos(0, 0); Console.Write('┌' + new string('─', w - 2) + '┐');
        for (var r = 1; r < h - 1; r++) { SetPos(0, r); Console.Write('│'); SetPos(w - 1, r); Console.Write('│'); }
        SetPos(0, h - 3); Console.Write('├' + new string('─', w - 2) + '┤');
        SetPos(0, h - 1); Console.Write('└' + new string('─', w - 2) + '┘');
    }

    private void RenderMessages()
    {
        var (w, h) = (Console.WindowWidth, Console.WindowHeight);
        var areaRows = h - 4;   // rows 1 .. h-4
        var areaCols = w - 2;

        Console.ResetColor();
        for (var r = 1; r <= areaRows; r++) { SetPos(1, r); Console.Write(new string(' ', areaCols)); }

        var visible = _messages.TakeLast(areaRows).ToList();
        var startRow = 1 + (areaRows - visible.Count);
        for (var i = 0; i < visible.Count; i++)
        {
            var (text, color) = visible[i];
            SetPos(1, startRow + i);
            Console.ForegroundColor = color;
            Console.Write(Fit(text, areaCols));
        }
    }

    private void RenderClientsPanel()
    {
        var (w, h) = (Console.WindowWidth, Console.WindowHeight);
        if (w < PanelWidth + 6) return;

        var left    = w - PanelWidth - 1;
        var innerW  = PanelWidth - 2;
        var maxRows = Math.Max(0, h - 8);
        var count   = Math.Min(_clients.Count, maxRows);

        Console.ForegroundColor = ConsoleColor.Blue;
        SetPos(left, 1); Console.Write('┌' + new string('─', innerW) + '┐');

        SetPos(left, 2); Console.Write('│');
        SetPos(left + 1, 2); Console.ForegroundColor = ConsoleColor.White;
        Console.Write(Fit($" Online ({_clients.Count})", innerW));
        Console.ForegroundColor = ConsoleColor.Blue;
        SetPos(left + PanelWidth - 1, 2); Console.Write('│');

        SetPos(left, 3); Console.Write('├' + new string('─', innerW) + '┤');

        for (var i = 0; i < count; i++)
        {
            Console.ForegroundColor = ConsoleColor.Blue;
            SetPos(left, 4 + i); Console.Write('│');
            SetPos(left + 1, 4 + i); Console.ForegroundColor = ConsoleColor.Red;
            Console.Write(Fit(" " + _clients[i], innerW));
            Console.ForegroundColor = ConsoleColor.Blue;
            SetPos(left + PanelWidth - 1, 4 + i); Console.Write('│');
        }

        Console.ForegroundColor = ConsoleColor.Blue;
        SetPos(left, 4 + count); Console.Write('└' + new string('─', innerW) + '┘');
    }

    private void RenderInputBar()
    {
        var (w, h) = (Console.WindowWidth, Console.WindowHeight);
        Console.ResetColor();
        SetPos(1, h - 2); Console.Write(new string(' ', w - 2));

        Console.ForegroundColor = ConsoleColor.Yellow;
        SetPos(1, h - 2); Console.Write(" > ");

        var maxLen  = w - 6;
        var display = _inputBuffer.Length > maxLen ? _inputBuffer[^maxLen..] : _inputBuffer;
        Console.ForegroundColor = ConsoleColor.White;
        Console.Write(display);
    }

    private void PositionCursor()
    {
        var (w, h) = (Console.WindowWidth, Console.WindowHeight);
        SetPos(Math.Min(4 + _inputBuffer.Length, w - 2), h - 2);
        Console.CursorVisible = true;
    }

    private static void SetPos(int col, int row)
    {
        try { Console.SetCursorPosition(col, row); }
        catch (ArgumentOutOfRangeException) { }
    }

    private static string Fit(string s, int width) =>
        s.Length <= width ? s.PadRight(width) : s[..width];
}
