import 'dart:async';
import 'package:flutter/material.dart';
import '../socket_service.dart';

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> me;
  final Map<String, dynamic> other;

  const ChatScreen({super.key, required this.me, required this.other});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  StreamSubscription? _msgSub;
  StreamSubscription? _histSub;

  int get _myId => widget.me['user_id'] as int;

  @override
  void initState() {
    super.initState();
    _histSub = SocketService.instance.history.listen((data) {
      if (mounted) {
        setState(() => _messages = data
            .map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m))
            .toList());
        _jumpToBottom();
      }
    });
    _msgSub = SocketService.instance.messages.listen((m) {
      final otherId = widget.other['id'] as int;
      final relevant = (m['sender_id'] == otherId && m['receiver_id'] == _myId) ||
          (m['sender_id'] == _myId && m['receiver_id'] == otherId);
      if (mounted && relevant) {
        setState(() => _messages.add(m));
        _jumpToBottom();
      }
    });
    SocketService.instance.loadHistory(widget.other['id'] as int);
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    SocketService.instance.sendMessage(widget.other['id'] as int, text);
    _input.clear();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _histSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = (m['sender_id'] as int) == _myId;
    final t = DateTime.fromMillisecondsSinceEpoch((m['timestamp'] as int) * 1000);
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: mine ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(m['text'],
                style: TextStyle(color: mine ? Colors.white : Colors.black87)),
            const SizedBox(height: 4),
            Text('$hh:$mm',
                style: TextStyle(
                    fontSize: 10,
                    color: mine ? Colors.white70 : Colors.black54)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.other['username']}')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _bubble(_messages[i]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Type a message',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
