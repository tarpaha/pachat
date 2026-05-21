import 'dart:convert';

import 'messages.dart';

String encodeLine(BaseMessage msg) => jsonEncode(msg.toJson());

BaseMessage? decodeLine(String line) {
  try {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) return null;
    return BaseMessage.fromJson(decoded);
  } catch (_) {
    return null;
  }
}
