import 'dart:convert';
import '../models/chat_event.dart';

/// Keeps histories from different databases separate, even at the same address.
class HistoryCache {
  String? activeDatabaseId;
  final Map<String, List<ChatEntry>> databases;
  final Map<String, int> cursors;

  HistoryCache(
    this.activeDatabaseId,
    this.databases, [
    Map<String, int>? cursors,
  ]) : cursors = cursors ?? {};

  static List<ChatEntry> _records(dynamic value) => (value as List)
      .map((e) => ChatEntry.fromJson(Map<String, dynamic>.from(e)))
      .toList();

  factory HistoryCache.decode(String? saved) {
    if (saved == null) return HistoryCache(null, {});
    final data = jsonDecode(saved) as Map<String, dynamic>;
    if (data['version'] != 3 && data['version'] != 4) {
      throw const FormatException('Unsupported history version');
    }
    return HistoryCache(
      data['activeDatabaseId'] as String?,
      (data['databases'] as Map<String, dynamic>).map(
        (id, records) => MapEntry(id, _records(records)),
      ),
      // Version 3 could contain holes from the old latest-20 history API.
      // Replay from zero once; existing blocks are deduplicated on ingestion.
      data['version'] == 4 ? Map<String, int>.from(data['cursors'] as Map) : {},
    );
  }

  List<ChatEntry> get preview => databases[activeDatabaseId] ?? [];

  String encode() => jsonEncode({
    'version': 4,
    'cursors': cursors,
    'activeDatabaseId': activeDatabaseId,
    'databases': databases.map(
      (id, records) => MapEntry(id, records.map((e) => e.toJson()).toList()),
    ),
  });
}
