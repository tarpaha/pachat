import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pachat_client/protocol/messages.dart';
import 'package:pachat_client/services/chat_service.dart';
import 'package:pachat_client/services/friends_repository.dart';
import 'friends_test.dart' show MemoryStorage;
import 'chat_service_test.dart' show until;

void send(Socket socket, Object value) =>
    socket.add(utf8.encode('${jsonEncode(value)}\n'));
Map<String, Object> block(int id) => {
  'type': 'new_block',
  'id': id,
  'block': 'block$id',
};
void page(Socket socket, int first, int last, bool more) => send(socket, {
  'type': 'history_page',
  'blocks': [for (var id = first; id <= last; id++) block(id)],
  'after_id': last,
  'has_more': more,
});
void hello(Socket socket) => send(socket, {
  'type': 'server_info',
  'database_id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'history_version': 2,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Interrupted catch-up resumes at saved page and ignores pre-history live events',
    () async {
      final listener = await ServerSocket.bind('127.0.0.1', 0);
      final connections = StreamIterator(listener);
      final disk = MemoryStorage();
      final friends = FriendsRepository(MemoryStorage());
      final service = await ChatService.connect(
        host: '127.0.0.1',
        port: listener.port,
        friends: friends,
        historyStorage: disk,
        reconnectDelay: const Duration(milliseconds: 20),
      );
      final peers = <Socket>[];
      final readers = <StreamIterator<String>>[];
      addTearDown(() async {
        await service.disconnect();
        service.dispose();
        for (final peer in peers) {
          peer.destroy();
        }
        for (final reader in readers) {
          await reader.cancel();
        }
        await connections.cancel();
        await listener.close();
        friends.dispose();
      });
      await connections.moveNext();
      var peer = connections.current;
      peers.add(peer);
      var requests = StreamIterator(readLines(peer));
      readers.add(requests);
      hello(peer);
      send(peer, block(250));
      await requests.moveNext();
      expect(jsonDecode(requests.current)['after_id'], 0);
      page(peer, 1, 100, true);
      await until(() => service.messages.cursor == 100);
      await service.messages.flush();
      expect(service.isConnecting, isTrue);
      expect(service.entries, hasLength(100));
      peer.destroy();

      await connections.moveNext().timeout(const Duration(seconds: 5));
      peer = connections.current;
      peers.add(peer);
      requests = StreamIterator(readLines(peer));
      readers.add(requests);
      hello(peer);
      await requests.moveNext();
      expect(jsonDecode(requests.current)['after_id'], 100);
      page(peer, 101, 200, true);
      page(peer, 201, 250, false);
      send(peer, block(251));
      send(peer, block(251));
      await until(
        () => service.messages.cursor == 251 && !service.isConnecting,
      );
      await service.messages.flush();
      expect(
        service.entries.map((e) => e.serverId),
        List.generate(251, (i) => i + 1),
      );
      expect(service.error, isNull);
      expect(jsonDecode(disk.value!)['cursors'].values.single, 251);
      await service.disconnect();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(service.isDisconnected, isTrue);
    },
  );

  test(
    'History protocol rejects pages that skip or rewind their advertised cursor',
    () {
      expect(
        () => HistoryPage.decode(
          jsonEncode({
            'type': 'history_page',
            'blocks': [block(5)],
            'after_id': 8,
            'has_more': false,
          }),
          0,
        ),
        throwsFormatException,
      );
      expect(
        () => HistoryPage.decode(
          jsonEncode({
            'type': 'history_page',
            'blocks': [block(5), block(4)],
            'after_id': 4,
            'has_more': false,
          }),
          0,
        ),
        throwsFormatException,
      );
      expect(
        () => HistoryPage.decode(
          jsonEncode({
            'type': 'history_page',
            'blocks': [],
            'after_id': 0,
            'has_more': true,
          }),
          0,
        ),
        throwsFormatException,
      );
    },
  );
}
