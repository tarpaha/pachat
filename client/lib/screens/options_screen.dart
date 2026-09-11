import 'package:flutter/material.dart';
import '../services/friends_repository.dart';
import '../services/prefs.dart';

class OptionsScreen extends StatefulWidget {
  final PrivateStorage storage;
  const OptionsScreen({super.key, required this.storage});

  @override
  State<OptionsScreen> createState() => _OptionsScreenState();
}

class _OptionsScreenState extends State<OptionsScreen> {
  final _host = TextEditingController();
  final _port = TextEditingController();
  final _form = GlobalKey<FormState>();
  LoginPrefs? _initial;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await Prefs.load(widget.storage);
      if (!mounted) return;
      _host.text = prefs.host;
      _port.text = '${prefs.port}';
      setState(() {
        _initial = prefs;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load options: $e');
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final prefs = LoginPrefs(
      host: _host.text.trim(),
      port: int.parse(_port.text),
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Prefs.save(widget.storage, prefs);
      if (!mounted) return;
      Navigator.pop(
        context,
        prefs.host != _initial!.host || prefs.port != _initial!.port,
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save options: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('Options')),
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
                    enabled: _initial != null && !_saving,
                    decoration: const InputDecoration(labelText: 'Server host'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _port,
                    enabled: _initial != null && !_saving,
                    decoration: const InputDecoration(labelText: 'Server port'),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return n == null || n < 1 || n > 65535
                          ? 'Invalid port'
                          : null;
                    },
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _initial != null && !_saving ? _save : null,
                    child: const Text('Save'),
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  if (_initial == null && _error != null)
                    TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
