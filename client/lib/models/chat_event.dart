class ChatEntry {
  final String digest;
  final String block;
  final int? serverId;
  final String? friendKey;
  final String? text;
  final DateTime timestamp;
  final bool fromSelf;
  final String status;
  const ChatEntry({
    required this.digest,
    required this.block,
    this.serverId,
    this.friendKey,
    this.text,
    required this.timestamp,
    this.fromSelf = false,
    this.status = 'received',
  });

  ChatEntry delivered(int id) => ChatEntry(
    digest: digest,
    block: block,
    serverId: id,
    friendKey: friendKey,
    text: text,
    timestamp: timestamp,
    fromSelf: fromSelf,
    status: 'stored',
  );
  ChatEntry uncertain() => ChatEntry(
    digest: digest,
    block: block,
    serverId: serverId,
    friendKey: friendKey,
    text: text,
    timestamp: timestamp,
    fromSelf: fromSelf,
    status: 'unconfirmed',
  );
  Map<String, dynamic> toJson() => {
    'digest': digest,
    'block': block,
    'serverId': serverId,
    'friendKey': friendKey,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'fromSelf': fromSelf,
    'status': status,
  };
  factory ChatEntry.fromJson(Map<String, dynamic> j) => ChatEntry(
    digest: j['digest'] as String,
    block: j['block'] as String,
    serverId: j['serverId'] as int?,
    friendKey: j['friendKey'] as String?,
    text: j['text'] as String?,
    timestamp: DateTime.parse(j['timestamp'] as String),
    fromSelf: j['fromSelf'] as bool,
    status: j['status'] as String,
  );
}
