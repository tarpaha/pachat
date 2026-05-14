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

public sealed record ConnectMessage(string Nickname, string Publickey)
    : BaseMessage;

public sealed record PeerJoinedMessage(string Nickname, string Publickey)
    : BaseMessage;

public sealed record PeerLeftMessage(string Nickname)
    : BaseMessage;

public sealed record PeerHelloMessage(
    string? To, string? From, string Nickname, string Publickey)
    : BaseMessage, IRoutable
{
    public BaseMessage WithFrom(string senderNick) => this with { To = null, From = senderNick };
}

public sealed record ChatMessage(
    string? To, string? From, string Timestamp, string Encryptedkey,
    string Iv, string Ciphertext, string Tag) : BaseMessage, IRoutable
{
    public BaseMessage WithFrom(string senderNick) => this with { To = null, From = senderNick };
}

public sealed record ErrorMessage(string Code, string Text)
    : BaseMessage;
