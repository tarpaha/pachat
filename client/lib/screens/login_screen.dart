import 'package:flutter/material.dart';
import '../services/profile_storage.dart';
import '../services/prefs.dart';
import 'chat_screen.dart';
import 'friends_screen.dart';
import 'options_screen.dart';

class LoginScreen extends StatefulWidget {
  final LocalProfile profile;
  final bool showProfileName;
  const LoginScreen({
    super.key,
    required this.profile,
    this.showProfileName = true,
  });
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _host = TextEditingController(text: '127.0.0.1');
  final _port = TextEditingController(text: '9000');
  final _form = GlobalKey<FormState>();
  get _friends => widget.profile.friends;
  bool _busy = false, _loaded = false, _configured = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    try {
      await _friends.load();
      final configured = await widget.profile.settings.read() != null;
      final prefs = await Prefs.load(widget.profile.settings);
      if (!mounted) return;
      _host.text = prefs.host;
      _port.text = '${prefs.port}';
      setState(() {
        _loaded = true;
        _configured = configured;
        _error = null;
      });
      if (configured) await _connect();
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load saved data: $e');
    }
  }

  Future<void> _connect() async {
    if (_busy) return;
    if (!_configured && !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final host = _host.text.trim(), port = int.parse(_port.text);
      if (!_configured) {
        await Prefs.save(
          widget.profile.settings,
          LoginPrefs(host: host, port: port),
        );
      }
      if (mounted) setState(() => _configured = true);
      bool reconnect;
      do {
        final prefs = await Prefs.load(widget.profile.settings);
        final host = prefs.host, port = prefs.port;
        final service = await widget.profile.connectChat(
          host: host,
          port: port,
          profileName: widget.showProfileName ? widget.profile.name : '',
        );
        if (!mounted) {
          return;
        }
        reconnect =
            await Navigator.push<bool>(
              context,
              MaterialPageRoute<bool>(
                builder: (_) => ChatScreen(
                  service: service,
                  settings: widget.profile.settings,
                ),
              ),
            ) ??
            false;
      } while (reconnect && mounted);
      if (mounted && widget.showProfileName && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not connect: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) widget.profile.chat?.reconnect();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _host.dispose();
    _port.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.showProfileName ? 'PaChat — ${widget.profile.name}' : 'PaChat',
      ),
      actions: [
        PopupMenuButton<String>(
          enabled: _loaded && !_busy,
          onSelected: (value) async {
            if (value == 'options') {
              final changed = await Navigator.push<bool>(
                context,
                MaterialPageRoute<bool>(
                  builder: (_) =>
                      OptionsScreen(storage: widget.profile.settings),
                ),
              );
              if (changed == true && mounted) await _load();
            } else {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => FriendsScreen(repository: _friends),
                ),
              );
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'friends', child: Text('Friends')),
            PopupMenuItem(value: 'options', child: Text('Options')),
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
                if (_loaded && !_configured) ...[
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
                ],
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
