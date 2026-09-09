import 'dart:convert';
import 'friends_repository.dart';

class LoginPrefs {
  final String host;
  final int port;
  const LoginPrefs({required this.host, required this.port});
}

class Prefs {
  static Future<LoginPrefs> load(PrivateStorage storage) async {
    final saved = await storage.read();
    if (saved == null) return const LoginPrefs(host: '127.0.0.1', port: 9000);
    final json = jsonDecode(saved) as Map<String, dynamic>;
    return LoginPrefs(host: json['host'] as String, port: json['port'] as int);
  }

  static Future<void> save(PrivateStorage storage, LoginPrefs value) =>
      storage.write(jsonEncode({'host': value.host, 'port': value.port}));
}
