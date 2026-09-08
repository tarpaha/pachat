import 'dart:convert';

const maxLineBytes = 1024 * 1024;

String encodePublish(String block) {
  final line = '${jsonEncode({'type': 'publish', 'block': block})}\n';
  if (utf8.encode(line).length > maxLineBytes - 64) {
    throw const FormatException('Message block is too large');
  }
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

Stream<String> boundedLines(Stream<List<int>> input) async* {
  var pending = <int>[];
  await for (final chunk in input) {
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] == 10) {
        if (pending.length + i - start + 1 > maxLineBytes) {
          throw const FormatException('Block too large');
        }
        pending.addAll(chunk.sublist(start, i));
        yield utf8.decode(pending);
        pending = <int>[];
        start = i + 1;
      }
    }
    if (pending.length + chunk.length - start >= maxLineBytes) {
      throw const FormatException('Block too large');
    }
    pending.addAll(chunk.sublist(start));
  }
  if (pending.isNotEmpty) throw const FormatException('Incomplete block');
}
