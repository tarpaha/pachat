import 'dart:convert';

String decodeDatabaseId(String line) {
  final json = jsonDecode(line) as Map<String, dynamic>;
  final id = json['database_id'];
  if (json['type'] != 'server_info' ||
      id is! String ||
      !RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) {
    throw const FormatException(
      'Server did not provide a valid database ID. Update the server.',
    );
  }
  if (json['history_version'] != 2) {
    throw const FormatException(
      'Server does not support full history. Update the server.',
    );
  }
  return id;
}

class HistoryPage {
  final List<NewBlock> blocks;
  final int afterId;
  final bool hasMore;
  const HistoryPage(this.blocks, this.afterId, this.hasMore);

  factory HistoryPage.decode(String line, int cursor) {
    final json = jsonDecode(line) as Map<String, dynamic>;
    if (json['type'] != 'history_page' ||
        json['blocks'] is! List ||
        json['after_id'] is! int ||
        json['has_more'] is! bool) {
      throw const FormatException('Invalid history page');
    }
    final blocks = (json['blocks'] as List)
        .map((value) => NewBlock.decode(jsonEncode(value)))
        .toList();
    if (blocks.length > 100) {
      throw const FormatException('Oversized history page');
    }
    for (final block in blocks) {
      if (block.id <= cursor) {
        throw const FormatException('Unordered history page');
      }
      cursor = block.id;
    }
    if (json['after_id'] != cursor ||
        (json['has_more'] == true && blocks.isEmpty)) {
      throw const FormatException('Invalid history cursor');
    }
    return HistoryPage(blocks, cursor, json['has_more'] as bool);
  }
}

String encodeHistory(int afterId) =>
    '${jsonEncode({'type': 'history', 'after_id': afterId})}\n';

String encodePublish(String block) {
  final line = '${jsonEncode({'type': 'publish', 'block': block})}\n';
  return line;
}

class NewBlock {
  final int id;
  final String block;
  const NewBlock(this.id, this.block);
  factory NewBlock.decode(String line) {
    final json = jsonDecode(line) as Map<String, dynamic>;
    if (json['type'] != 'new_block' ||
        json['id'] is! int ||
        (json['id'] as int) < 1 ||
        json['block'] is! String) {
      throw const FormatException('Invalid new_block');
    }
    return NewBlock(json['id'] as int, json['block'] as String);
  }
}

Stream<String> readLines(Stream<List<int>> input) async* {
  var pending = <int>[];
  await for (final chunk in input) {
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] == 10) {
        pending.addAll(chunk.sublist(start, i));
        yield utf8.decode(pending);
        pending = <int>[];
        start = i + 1;
      }
    }
    pending.addAll(chunk.sublist(start));
  }
  if (pending.isNotEmpty) throw const FormatException('Incomplete block');
}
