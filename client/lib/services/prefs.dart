import 'package:shared_preferences/shared_preferences.dart';

class LoginPrefs {
  final String host;
  final int port;
  const LoginPrefs({required this.host, required this.port});
}

class Prefs {
  static Future<LoginPrefs> load() async {
    final p = await SharedPreferences.getInstance();
    return LoginPrefs(
      host: p.getString('host') ?? '127.0.0.1',
      port: p.getInt('port') ?? 9000,
    );
  }

  static Future<void> save(LoginPrefs value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('host', value.host);
    await p.setInt('port', value.port);
    await p.remove('nickname');
  }
}
