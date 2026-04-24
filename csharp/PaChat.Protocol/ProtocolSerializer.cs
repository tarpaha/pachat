using System.Text.Json;

namespace PaChat.Protocol;

public static class ProtocolSerializer
{
    private static readonly JsonSerializerOptions Options = new()
    {
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };

    public static BaseMessage? Deserialize(string line)
        => JsonSerializer.Deserialize<BaseMessage>(line, Options);

    public static string Serialize(BaseMessage message)
        => JsonSerializer.Serialize<BaseMessage>(message, Options);
}
