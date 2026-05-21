import 'dart:async';

import 'package:flutter/material.dart';

import '../models/chat_event.dart';
import '../services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final ChatService service;
  const ChatScreen({super.key, required this.service});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<ChatEvent> _events = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  StreamSubscription<ChatEvent>? _sub;
  bool _disconnected = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.events.listen(_onEvent);
  }

  void _onEvent(ChatEvent ev) {
    setState(() {
      _events.add(ev);
      if (ev is DisconnectedEvent) _disconnected = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    if (_disconnected) return;
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    _inputController.clear();
    await widget.service.sendChat(text);
    _inputFocus.requestFocus();
  }

  Future<void> _exit() async {
    await widget.service.disconnect();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.service.disconnect();
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _exit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('PaChat — ${widget.service.nickname}'),
          actions: [
            IconButton(
              tooltip: 'Exit',
              icon: const Icon(Icons.logout),
              onPressed: _exit,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: _events.length,
                  itemBuilder: (_, i) => _EventTile(event: _events[i]),
                ),
              ),
              if (_disconnected)
                Container(
                  width: double.infinity,
                  color: Colors.red.withValues(alpha: 0.2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: const Text(
                    'Disconnected from server. Tap exit to return.',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _inputController,
                          focusNode: _inputFocus,
                          enabled: !_disconnected,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: _disconnected
                                ? 'Disconnected'
                                : 'Type a message…',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _disconnected ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final ChatEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    switch (event) {
      case ChatLineEvent(:final from, :final timestamp, :final text, :final fromSelf):
        final hh = timestamp.toLocal().hour.toString().padLeft(2, '0');
        final mm = timestamp.toLocal().minute.toString().padLeft(2, '0');
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: '[$hh:$mm] ',
                  style: const TextStyle(color: Colors.grey),
                ),
                TextSpan(
                  text: '<$from> ',
                  style: TextStyle(
                    color: fromSelf ? Colors.cyanAccent : Colors.lightBlueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(text: text),
              ],
            ),
          ),
        );
      case PeerJoinedEvent(:final nickname):
        return _SystemLine('*** $nickname joined', Colors.amber);
      case PeerLeftEvent(:final nickname):
        return _SystemLine('*** $nickname left', Colors.amber);
      case SystemErrorEvent(:final code, :final text):
        return _SystemLine('error $code: $text', Colors.redAccent);
      case DisconnectedEvent(:final reason):
        return _SystemLine('*** disconnected ($reason)', Colors.redAccent);
    }
  }
}

class _SystemLine extends StatelessWidget {
  final String text;
  final Color color;
  const _SystemLine(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: TextStyle(color: color, fontStyle: FontStyle.italic),
      ),
    );
  }
}
