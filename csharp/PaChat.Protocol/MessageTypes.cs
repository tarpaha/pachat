using System.Text.Json.Serialization;

namespace PaChat.Protocol;

[JsonPolymorphic(TypeDiscriminatorPropertyName = "type")]
[JsonDerivedType(typeof(ConnectMessage),    "connect")]
[JsonDerivedType(typeof(PeerJoinedMessage), "peerjoined")]
[JsonDerivedType(typeof(PeerLeftMessage),   "peerleft")]
[JsonDerivedType(typeof(PeerHelloMessage),  "peerhello")]
[JsonDerivedType(typeof(ChatMessage),       "chat")]
[JsonDerivedType(typeof(ErrorMessage),      "error")]
public abstract record BaseMessage;

public interface IRoutable
{
    string? To { get; }
    BaseMessage WithFrom(string senderNick);
}

public sealed record ConnectMessage(
    [property: JsonPropertyName("nickname")]  string Nickname,
    [property: JsonPropertyName("publicKey")] string PublicKey)
    : BaseMessage;

public sealed record PeerJoinedMessage(
    [property: JsonPropertyName("nickname")]  string Nickname,
    [property: JsonPropertyName("publicKey")] string PublicKey)
    : BaseMessage;

public sealed record PeerLeftMessage(
    [property: JsonPropertyName("nickname")] string Nickname)
    : BaseMessage;

public sealed record PeerHelloMessage(
    [property: JsonPropertyName("to")]        string? To,
    [property: JsonPropertyName("from")]      string? From,
    [property: JsonPropertyName("nickname")]  string Nickname,
    [property: JsonPropertyName("publicKey")] string PublicKey)
    : BaseMessage, IRoutable
{
    public BaseMessage WithFrom(string senderNick) => this with { To = null, From = senderNick };
}

public sealed record ChatMessage(
    [property: JsonPropertyName("to")]           string? To,
    [property: JsonPropertyName("from")]         string? From,
    [property: JsonPropertyName("timestamp")]    string Timestamp,
    [property: JsonPropertyName("encryptedKey")] string EncryptedKey,
    [property: JsonPropertyName("iv")]           string Iv,
    [property: JsonPropertyName("ciphertext")]   string Ciphertext,
    [property: JsonPropertyName("tag")]          string Tag)
    : BaseMessage, IRoutable
{
    public BaseMessage WithFrom(string senderNick) => this with { To = null, From = senderNick };
}

public sealed record ErrorMessage(
    [property: JsonPropertyName("code")] string Code,
    [property: JsonPropertyName("text")] string Text)
    : BaseMessage;
