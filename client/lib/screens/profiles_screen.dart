import 'package:flutter/material.dart';
import '../services/profile_storage.dart';
import 'login_screen.dart';

class ProfilesScreen extends StatefulWidget {
  final ProfileCatalog? catalog;
  const ProfilesScreen({super.key, this.catalog});
  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  final _name = TextEditingController();
  ProfileCatalog? _catalog;
  List<String> _names = [];
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final catalog = widget.catalog ?? await ProfileCatalog.device();
      final names = await catalog.names();
      if (mounted) {
        setState(() {
          _catalog = catalog;
          _names = names;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _open(String name) async {
    if (_busy || _catalog == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    LocalProfile? profile;
    try {
      profile = await _catalog!.open(name);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => LoginScreen(profile: profile!)),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Could not open profile. It may already be open in another window. $e',
        );
      }
    } finally {
      await profile?.close();
      if (mounted) {
        setState(() => _busy = false);
        if (_error == null) await _load();
      }
    }
  }

  Future<void> _delete(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete profile "$name"?'),
        content: const Text(
          'This permanently deletes this profile’s friends, private keys, saved messages and settings. Export a key backup first if you want to restore your friends and keys later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _catalog!.delete(name);
      await _load();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Could not delete profile. Close it in other windows first. $e',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PaChat — Profiles')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                'Choose your local profile. Friends and keys are kept between sessions.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: 'Profile name'),
                onSubmitted: _open,
              ),
              FilledButton(
                onPressed: _busy || _catalog == null
                    ? null
                    : () => _open(_name.text),
                child: const Text('Create / open profile'),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              Expanded(
                child: ListView(
                  children: [
                    for (final name in _names)
                      ListTile(
                        title: Text(name),
                        leading: const Icon(Icons.person),
                        trailing: IconButton(
                          tooltip: 'Delete profile',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy ? null : () => _delete(name),
                        ),
                        onTap: _busy ? null : () => _open(name),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
