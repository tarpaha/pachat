sealed class ChatEvent {
  const ChatEvent();
}

class ChatLineEvent extends ChatEvent {
  final String from;
  final DateTime timestamp;
  final String text;
  final bool fromSelf;
  const ChatLineEvent({
    required this.from,
    required this.timestamp,
    required this.text,
    required this.fromSelf,
  });
}

class PeerJoinedEvent extends ChatEvent {
  final String nickname;
  const PeerJoinedEvent(this.nickname);
}

class PeerLeftEvent extends ChatEvent {
  final String nickname;
  const PeerLeftEvent(this.nickname);
}

class SystemErrorEvent extends ChatEvent {
  final String code;
  final String text;
  const SystemErrorEvent(this.code, this.text);
}

class DisconnectedEvent extends ChatEvent {
  final String reason;
  const DisconnectedEvent(this.reason);
}
