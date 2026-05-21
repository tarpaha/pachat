sealed class BaseMessage {
  const BaseMessage();

  Map<String, dynamic> toJson();

  static BaseMessage? fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String) return null;
    switch (type) {
      case 'connect':
        return ConnectMessage(
          nickname: json['nickname'] as String,
          publickey: json['publickey'] as String,
        );
      case 'peerjoined':
        return PeerJoinedMessage(
          nickname: json['nickname'] as String,
          publickey: json['publickey'] as String,
        );
      case 'peerleft':
        return PeerLeftMessage(nickname: json['nickname'] as String);
      case 'peerhello':
        return PeerHelloMessage(
          to: json['to'] as String?,
          from: json['from'] as String?,
          nickname: json['nickname'] as String,
          publickey: json['publickey'] as String,
        );
      case 'chat':
        return ChatMessage(
          to: json['to'] as String?,
          from: json['from'] as String?,
          timestamp: json['timestamp'] as String,
          encryptedkey: json['encryptedkey'] as String,
          iv: json['iv'] as String,
          ciphertext: json['ciphertext'] as String,
          tag: json['tag'] as String,
        );
      case 'error':
        return ErrorMessage(
          code: json['code'] as String,
          text: json['text'] as String,
        );
      default:
        return null;
    }
  }
}

class ConnectMessage extends BaseMessage {
  final String nickname;
  final String publickey;
  const ConnectMessage({required this.nickname, required this.publickey});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'connect',
    'nickname': nickname,
    'publickey': publickey,
  };
}

class PeerJoinedMessage extends BaseMessage {
  final String nickname;
  final String publickey;
  const PeerJoinedMessage({required this.nickname, required this.publickey});

  @override
  Map<String, dynamic> toJson() => {
    'type': 'peerjoined',
    'nickname': nickname,
    'publickey': publickey,
  };
}

class PeerLeftMessage extends BaseMessage {
  final String nickname;
  const PeerLeftMessage({required this.nickname});

  @override
  Map<String, dynamic> toJson() => {'type': 'peerleft', 'nickname': nickname};
}

class PeerHelloMessage extends BaseMessage {
  final String? to;
  final String? from;
  final String nickname;
  final String publickey;
  const PeerHelloMessage({
    this.to,
    this.from,
    required this.nickname,
    required this.publickey,
  });

  @override
  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'type': 'peerhello'};
    if (to != null) m['to'] = to;
    if (from != null) m['from'] = from;
    m['nickname'] = nickname;
    m['publickey'] = publickey;
    return m;
  }
}

class ChatMessage extends BaseMessage {
  final String? to;
  final String? from;
  final String timestamp;
  final String encryptedkey;
  final String iv;
  final String ciphertext;
  final String tag;
  const ChatMessage({
    this.to,
    this.from,
    required this.timestamp,
    required this.encryptedkey,
    required this.iv,
    required this.ciphertext,
    required this.tag,
  });

  @override
  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'type': 'chat'};
    if (to != null) m['to'] = to;
    if (from != null) m['from'] = from;
    m['timestamp'] = timestamp;
    m['encryptedkey'] = encryptedkey;
    m['iv'] = iv;
    m['ciphertext'] = ciphertext;
    m['tag'] = tag;
    return m;
  }
}

class ErrorMessage extends BaseMessage {
  final String code;
  final String text;
  const ErrorMessage({required this.code, required this.text});

  @override
  Map<String, dynamic> toJson() => {'type': 'error', 'code': code, 'text': text};
}
