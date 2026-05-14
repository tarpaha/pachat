using System.Text.Json;
using System.Text.Json.Serialization;

namespace PaChat.Protocol;

public static class ProtocolSerializer
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static BaseMessage? Deserialize(string line)
        => JsonSerializer.Deserialize<BaseMessage>(line, Options);

    public static string Serialize(BaseMessage message)
        => JsonSerializer.Serialize(message, Options);
}
