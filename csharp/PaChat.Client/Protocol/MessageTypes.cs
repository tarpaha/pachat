using System.Text.Json.Serialization;

namespace PaChat.Client.Protocol;

[JsonPolymorphic(TypeDiscriminatorPropertyName = "type")]
[JsonDerivedType(typeof(ConnectMessage),      "connect")]
[JsonDerivedType(typeof(KeyExchangeMessage),  "keyexchange")]
[JsonDerivedType(typeof(EncryptedMessage),    "message")]
[JsonDerivedType(typeof(BroadcastMessage),    "broadcast")]
[JsonDerivedType(typeof(SystemMessage),       "system")]
[JsonDerivedType(typeof(ErrorMessage),        "error")]
public abstract record BaseMessage;

public sealed record ConnectMessage(
    [property: JsonPropertyName("nickname")]  string Nickname,
    [property: JsonPropertyName("publicKey")] string PublicKey)
    : BaseMessage;

public sealed record KeyExchangeMessage(
    [property: JsonPropertyName("serverPublicKey")] string ServerPublicKey)
    : BaseMessage;

public sealed record EncryptedMessage(
    [property: JsonPropertyName("encryptedKey")] string EncryptedKey,
    [property: JsonPropertyName("iv")]           string Iv,
    [property: JsonPropertyName("ciphertext")]   string Ciphertext,
    [property: JsonPropertyName("tag")]          string Tag)
    : BaseMessage;

public sealed record BroadcastMessage(
    [property: JsonPropertyName("nickname")]     string Nickname,
    [property: JsonPropertyName("timestamp")]    string Timestamp,
    [property: JsonPropertyName("encryptedKey")] string EncryptedKey,
    [property: JsonPropertyName("iv")]           string Iv,
    [property: JsonPropertyName("ciphertext")]   string Ciphertext,
    [property: JsonPropertyName("tag")]          string Tag)
    : BaseMessage;

public sealed record SystemMessage(
    [property: JsonPropertyName("text")]      string Text,
    [property: JsonPropertyName("timestamp")] string Timestamp)
    : BaseMessage;

public sealed record ErrorMessage(
    [property: JsonPropertyName("code")] string Code,
    [property: JsonPropertyName("text")] string Text)
    : BaseMessage;
