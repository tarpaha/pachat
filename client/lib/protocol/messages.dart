import 'dart:convert';

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
