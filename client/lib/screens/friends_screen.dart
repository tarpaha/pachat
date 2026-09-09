import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
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

  Future<void> _add() async {
    final values = await _ask('Add friend', ['Friend name']);
    if (values == null || !mounted) return;
    await _run(() => widget.repository.create(values[0]));
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

  Future<void> _share(FriendKey friend, BuildContext buttonContext) async {
    final box = buttonContext.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    await _run(() async {
      await SharePlus.instance.share(
        ShareParams(
          text: friend.publicKey,
          title: 'PaChat public key',
          sharePositionOrigin: origin,
        ),
      );
    });
  }

  Future<void> _acceptKey(FriendKey friend, String value) async {
    if (friend.peerPublicKey != null && friend.peerPublicKey != value.trim()) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace friend’s public key?'),
          content: const Text(
            'Future messages will use the new key. Your key for reading this friend’s messages stays the same.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    await _run(() => widget.repository.setPeerKey(friend, value));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
    ),
    body: ListenableBuilder(
      listenable: widget.repository,
      builder: (_, _) => Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.person_add),
              label: const Text('Add friend'),
            ),
          ),
          Expanded(
            child: widget.repository.friends.isEmpty
                ? const Center(
                    child: Text('Add a friend, then exchange public keys.'),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: widget.repository.friends.length,
                    itemBuilder: (_, i) {
                      final friend = widget.repository.friends[i];
                      return _FriendCard(
                        key: ValueKey(friend.id),
                        friend: friend,
                        busy: _busy,
                        onShare: (context) => _share(friend, context),
                        onCopy: () => _run(() async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(
                            ClipboardData(text: friend.publicKey),
                          );
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Public key copied. Send it to this friend.',
                                ),
                              ),
                            );
                          }
                        }),
                        onSave: (value) => _acceptKey(friend, value),
                        onRename: () => _rename(friend),
                        onDelete: () => _remove(friend),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

class _FriendCard extends StatefulWidget {
  final FriendKey friend;
  final bool busy;
  final void Function(BuildContext) onShare;
  final VoidCallback onCopy, onRename, onDelete;
  final void Function(String) onSave;
  const _FriendCard({
    super.key,
    required this.friend,
    required this.busy,
    required this.onShare,
    required this.onCopy,
    required this.onSave,
    required this.onRename,
    required this.onDelete,
  });
  @override
  State<_FriendCard> createState() => _FriendCardState();
}

class _FriendCardState extends State<_FriendCard> {
  late final _keyInput = TextEditingController(
    text: widget.friend.peerPublicKey ?? '',
  );
  @override
  void didUpdateWidget(covariant _FriendCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.friend.peerPublicKey != widget.friend.peerPublicKey) {
      _keyInput.text = widget.friend.peerPublicKey ?? '';
    }
  }

  @override
  void dispose() {
    _keyInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.friend.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              PopupMenuButton<String>(
                enabled: !widget.busy,
                onSelected: (value) {
                  if (value == 'rename') {
                    widget.onRename();
                  } else {
                    widget.onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Send this public key to your friend so you can read their messages.',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Builder(
                builder: (context) => FilledButton.icon(
                  onPressed: widget.busy ? null : () => widget.onShare(context),
                  icon: const Icon(Icons.share),
                  label: const Text('Share public key'),
                ),
              ),
              OutlinedButton.icon(
                onPressed: widget.busy ? null : widget.onCopy,
                icon: const Icon(Icons.copy),
                label: const Text('Copy key'),
              ),
            ],
          ),
          const Divider(height: 32),
          const Text(
            'Ask your friend for their public key and paste it here so they can read your messages.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _keyInput,
            enabled: !widget.busy,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Friend’s public key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                onPressed: widget.busy
                    ? null
                    : () => widget.onSave(_keyInput.text),
                child: const Text('Save friend’s key'),
              ),
              Text(
                widget.friend.peerPublicKey == null
                    ? 'Key not added — this friend cannot read your messages yet.'
                    : 'Key saved — this friend is included when you send.',
              ),
            ],
          ),
        ],
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
