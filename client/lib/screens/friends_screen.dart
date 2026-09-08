import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../crypto/backup_crypto.dart';
import '../services/friends_repository.dart';

class FriendsScreen extends StatefulWidget {
  final FriendsRepository repository;
  const FriendsScreen({super.key, required this.repository});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<String>?> _ask(
    String title,
    List<String> labels, {
    String initial = '',
    bool password = false,
  }) => showDialog<List<String>>(
    context: context,
    builder: (_) => _InputDialog(
      title: title,
      labels: labels,
      initial: initial,
      password: password,
    ),
  );

  Future<void> _add(bool created) async {
    final values = await _ask(
      created ? 'Create friend' : 'Import public key',
      created ? ['Friend name'] : ['Friend name', 'Public key'],
    );
    if (values == null || !mounted) return;
    await _run(
      () => created
          ? widget.repository.create(values[0])
          : widget.repository.importKey(values[0], values[1]),
    );
  }

  Future<void> _rename(FriendKey friend) async {
    final values = await _ask('Rename friend', [
      'Friend name',
    ], initial: friend.name);
    if (values == null || !mounted) return;
    await _run(() => widget.repository.rename(friend, values[0]));
  }

  Future<void> _remove(FriendKey friend) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${friend.name}?'),
        content: Text(
          friend.pair != null
              ? 'The private key will be deleted. Without a backup you cannot decrypt blocks for this key again.'
              : 'Future messages will no longer include a copy for this public key.',
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
    if (confirm != true || !mounted) return;
    await _run(() => widget.repository.remove(friend));
  }

  Future<void> _showText(String title, String text) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(child: SelectableText(text)),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: text));
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Copied')));
            }
          },
          child: const Text('Copy'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _backup(bool restore) async {
    final values = await _ask(
      restore ? 'Restore friends' : 'Back up friends',
      restore
          ? ['Password', 'Encrypted backup']
          : ['Password (at least 12 characters)'],
      password: true,
    );
    if (values == null || !mounted) return;
    await _run(() async {
      if (restore) {
        final json = await compute(decryptBackup, (values[1], values[0]));
        await widget.repository.restore(json);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Friends restored. Existing keys kept.'),
            ),
          );
        }
      } else {
        final backup = await compute(encryptBackup, (
          widget.repository.exportJson(),
          values[0],
        ));
        if (mounted) await _showText('Save this encrypted backup', backup);
      }
    });
  }

  Widget _list(bool created) {
    final friends = created
        ? widget.repository.created
        : widget.repository.received;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            created
                ? 'Create a separate key pair for each friend. Share only the public key with that person.'
                : 'Import keys sent to you. Each message includes a copy for every key in this list.',
          ),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : () => _add(created),
          icon: const Icon(Icons.add),
          label: Text(created ? 'Create friend' : 'Import public key'),
        ),
        Expanded(
          child: friends.isEmpty
              ? const Center(child: Text('No friends yet'))
              : ListView.builder(
                  itemCount: friends.length,
                  itemBuilder: (context, i) {
                    final friend = friends[i];
                    return ListTile(
                      title: Text(friend.name),
                      subtitle: Text(
                        created
                            ? 'Private key saved on this device'
                            : 'Receives your messages',
                      ),
                      trailing: PopupMenuButton<String>(
                        enabled: !_busy,
                        onSelected: (value) {
                          switch (value) {
                            case 'key':
                              _showText(
                                'Public key — ${friend.name}',
                                friend.publicKey,
                              );
                            case 'rename':
                              _rename(friend);
                            case 'delete':
                              _remove(friend);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'key',
                            child: Text('Show public key'),
                          ),
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          PopupMenuButton<String>(
            enabled: !_busy,
            onSelected: (value) => _backup(value == 'restore'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'backup', child: Text('Encrypted backup')),
              PopupMenuItem(value: 'restore', child: Text('Restore backup')),
            ],
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Created by me'),
            Tab(text: 'Received keys'),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.repository,
        builder: (_, _) => Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            Expanded(child: TabBarView(children: [_list(true), _list(false)])),
          ],
        ),
      ),
    ),
  );
}

class _InputDialog extends StatefulWidget {
  final String title;
  final List<String> labels;
  final String initial;
  final bool password;
  const _InputDialog({
    required this.title,
    required this.labels,
    required this.initial,
    required this.password,
  });
  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final _controllers = List.generate(
    widget.labels.length,
    (i) => TextEditingController(text: i == 0 ? widget.initial : ''),
  );
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _controllers.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: TextFormField(
                    controller: _controllers[i],
                    autofocus: i == 0,
                    obscureText: widget.password && i == 0,
                    minLines: i == 0 ? 1 : 3,
                    maxLines: i == 0 ? 1 : 6,
                    decoration: InputDecoration(labelText: widget.labels[i]),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Required'
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _controllers.map((e) => e.text).toList());
          }
        },
        child: const Text('Continue'),
      ),
    ],
  );
}
