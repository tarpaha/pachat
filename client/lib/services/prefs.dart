import 'package:shared_preferences/shared_preferences.dart';

class LoginPrefs {
  final String host;
  final int port;
  final String nickname;
  const LoginPrefs({
    required this.host,
    required this.port,
    required this.nickname,
  });
}

class Prefs {
  static const _kHost = 'host';
  static const _kPort = 'port';
  static const _kNickname = 'nickname';

  static Future<LoginPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return LoginPrefs(
      host: p.getString(_kHost) ?? '127.0.0.1',
      port: p.getInt(_kPort) ?? 9000,
      nickname: p.getString(_kNickname) ?? '',
    );
  }

  static Future<void> save(LoginPrefs v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kHost, v.host);
    await p.setInt(_kPort, v.port);
    await p.setString(_kNickname, v.nickname);
  }
}
