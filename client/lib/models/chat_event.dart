class ChatEntry {
  final int serverId;
  final String block;
  final String? friendKey;
  final String? text;
  final DateTime? timestamp;
  final bool fromSelf;
  const ChatEntry({
    required this.serverId,
    required this.block,
    this.friendKey,
    this.text,
    this.timestamp,
    this.fromSelf = false,
  });
  // Only the original server record is persisted. Decrypted fields are ephemeral.
  Map<String, dynamic> toJson() => {'id': serverId, 'block': block};
  factory ChatEntry.fromJson(Map<String, dynamic> json) =>
      ChatEntry(serverId: json['id'] as int, block: json['block'] as String);
}
