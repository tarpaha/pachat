import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import 'friends_screen.dart';

class ChatScreen extends StatefulWidget {
  final ChatService service;
  const ChatScreen({super.key, required this.service});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;
  @override
  void initState() {
    super.initState();
    widget.service.addListener(_changed);
    widget.service.friends.addListener(_changed);
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    if (_sending || _input.text.trim().isEmpty) return;
    final text = _input.text;
    setState(() => _sending = true);
    try {
      await widget.service.sendChat(text);
      if (!mounted) return;
      if (_input.text == text) _input.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    widget.service.removeListener(_changed);
    widget.service.friends.removeListener(_changed);

    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final canSend =
        !service.isDisconnected &&
        service.friends.received.isNotEmpty &&
        !_sending;
    return Scaffold(
      appBar: AppBar(
        title: Text('PaChat — ${service.profileName}'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => FriendsScreen(repository: service.friends),
              ),
            ),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'friends', child: Text('Friends')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: service.entries.isEmpty
                  ? const Center(child: Text('New messages will appear here'))
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: service.entries.length,
                      itemBuilder: (_, i) {
                        final entry = service.entries[i];
                        final matches = service.friends.created.where(
                          (f) => f.id == entry.friendKey,
                        );
                        final name = matches.isNotEmpty
                            ? matches.first.name
                            : 'Unknown source';
                        final time = entry.timestamp?.toLocal();
                        final clock = time == null
                            ? ''
                            : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                  SelectableText(
                                    entry.text ??
                                        'Unknown message from an unknown source',
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$clock · #${entry.serverId}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (service.isDisconnected)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Disconnected. Return to reconnect.'),
              ),
            if (service.error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  service.error!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            if (service.storageError != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    Text(
                      service.storageError!,
                      style: const TextStyle(color: Colors.amber),
                    ),
                    TextButton(
                      onPressed: service.retrySave,
                      child: const Text('Retry saving history'),
                    ),
                  ],
                ),
              ),
            if (service.friends.received.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text(
                  'Open Friends and import a public key to send messages.',
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: !service.isDisconnected && !_sending,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) {
                        if (canSend) _send();
                      },
                      decoration: const InputDecoration(
                        hintText: 'Type a message…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Send to all received keys',
                    onPressed: canSend ? _send : null,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
