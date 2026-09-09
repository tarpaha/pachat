import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../services/profile_storage.dart';
import '../services/prefs.dart';
import 'chat_screen.dart';
import 'friends_screen.dart';

class LoginScreen extends StatefulWidget {
  final LocalProfile profile;
  const LoginScreen({super.key, required this.profile});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _host = TextEditingController(text: '127.0.0.1');
  final _port = TextEditingController(text: '9000');
  final _form = GlobalKey<FormState>();
  get _friends => widget.profile.friends;
  bool _busy = false, _loaded = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _friends.load();
      final prefs = await Prefs.load(widget.profile.settings);
      if (!mounted) return;
      _host.text = prefs.host;
      _port.text = '${prefs.port}';
      setState(() {
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load saved data: $e');
    }
  }

  Future<void> _connect() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final host = _host.text.trim(), port = int.parse(_port.text);
      await Prefs.save(
        widget.profile.settings,
        LoginPrefs(host: host, port: port),
      );
      final service = await ChatService.connect(
        host: host,
        port: port,
        friends: _friends,
        historyStorage: widget.profile.history('$host:$port'),
        profileName: widget.profile.name,
      );
      if (!mounted) {
        service.dispose();
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => ChatScreen(service: service)),
      );
      await service.disconnect();
      service.dispose();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('PaChat — ${widget.profile.name}'),
      actions: [
        PopupMenuButton<String>(
          enabled: _loaded && !_busy,
          onSelected: (_) => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => FriendsScreen(repository: _friends),
            ),
          ),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'friends', child: Text('Friends')),
          ],
        ),
      ],
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _host,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'Server host'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _port,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Server port'),
                  onFieldSubmitted: (_) {
                    if (_loaded) _connect();
                  },
                  validator: (v) {
                    final n = int.tryParse(v ?? '');
                    return n == null || n < 1 || n > 65535
                        ? 'Invalid port'
                        : null;
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loaded && !_busy ? _connect : null,
                  child: Text(_busy ? 'Connecting…' : 'Connect'),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                if (!_loaded && _error != null)
                  TextButton(
                    onPressed: _load,
                    child: const Text('Retry loading saved data'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
