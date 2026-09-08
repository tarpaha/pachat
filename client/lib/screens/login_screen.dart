import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/prefs.dart';
import 'chat_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _busy = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await Prefs.load();
    if (!mounted) return;
    _hostController.text = prefs.host;
    _portController.text = prefs.port.toString();
    _nicknameController.text = prefs.nickname;
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _onEnter() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final host = _hostController.text.trim();
    final port = int.parse(_portController.text.trim());
    final nickname = _nicknameController.text.trim();

    setState(() {
      _busy = true;
      _errorText = null;
    });

    await Prefs.save(
      LoginPrefs(host: host, port: port, nickname: nickname),
    );

    try {
      final service = await ChatService.connectAndRegister(
        host: host,
        port: port,
        nickname: nickname,
      );
      if (!mounted) {
        await service.disconnect();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(service: service)),
      );
    } on LoginException catch (e) {
      if (!mounted) return;
      setState(() => _errorText = '${e.code}: ${e.text}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PaChat — Login')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextFormField(
                      controller: _hostController,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Server host',
                        hintText: '127.0.0.1',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _portController,
                      enabled: !_busy,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Server port',
                        hintText: '9000',
                      ),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return 'Required';
                        final n = int.tryParse(t);
                        if (n == null || n <= 0 || n > 65535) {
                          return 'Invalid port';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _nicknameController,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Nickname',
                      ),
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _onEnter(),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return 'Required';
                        if (t.length > 32) return 'Max 32 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _onEnter,
                        child: _busy
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Enter'),
                      ),
                    ),
                    if (_errorText != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.red.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          _errorText!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
