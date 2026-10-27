import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
  StreamSubscription? _readSub;
  StreamSubscription? _delSub;
  StreamSubscription? _typingSub;

  Timer? _typingDebounce;
  bool _otherIsTyping = false;
  bool _showScrollBottom = false;

  int get _myId => widget.me['user_id'] as int;
  int get _otherId => widget.other['id'] as int;

  @override
  void initState() {
    super.initState();

    _histSub = SocketService.instance.history.listen((data) {
      if (mounted) {
        setState(() {
          _messages = data.map<Map<String, dynamic>>((m) => Map<String, dynamic>.from(m)).toList();
        });
        _jumpToBottom();
      }
    });

    _msgSub = SocketService.instance.messages.listen((m) {
      final relevant = (m['sender_id'] == _otherId && m['receiver_id'] == _myId) ||
          (m['sender_id'] == _myId && m['receiver_id'] == _otherId);
      if (mounted && relevant) {
        setState(() {
          // Prevent duplicates by client_id or id
          final idx = _messages.indexWhere((existing) =>
              (existing['id'] != null && existing['id'] == m['id']) ||
              (existing['client_id'] != null && existing['client_id'] == m['client_id']));
          if (idx != -1) {
            _messages[idx] = m;
          } else {
            _messages.add(m);
          }
        });
        if (m['sender_id'] == _otherId) {
          SocketService.instance.markAsRead(_otherId);
        }
        _jumpToBottom();
      }
    });

    _readSub = SocketService.instance.messagesRead.listen((data) {
      if (mounted && data['by_user_id'] == _otherId) {
        setState(() {
          for (var msg in _messages) {
            if (msg['sender_id'] == _myId) {
              msg['status'] = 'read';
            }
          }
        });
      }
    });

    _delSub = SocketService.instance.messageDeleted.listen((data) {
      final msgId = data['message_id'];
      if (mounted && msgId != null) {
        setState(() {
          for (var msg in _messages) {
            if (msg['id'] == msgId) {
              msg['deleted'] = 1;
              msg['text'] = 'This message was deleted';
            }
          }
        });
      }
    });

    _typingSub = SocketService.instance.typing.listen((data) {
      if (mounted && data['user_id'] == _otherId) {
        setState(() {
          _otherIsTyping = data['is_typing'] == true;
        });
        if (_otherIsTyping) _jumpToBottom();
      }
    });

    _scroll.addListener(() {
      if (_scroll.hasClients) {
        final diff = _scroll.position.maxScrollExtent - _scroll.offset;
        if (diff > 300 && !_showScrollBottom) {
          setState(() => _showScrollBottom = true);
        } else if (diff <= 300 && _showScrollBottom) {
          setState(() => _showScrollBottom = false);
        }
      }
    });

    SocketService.instance.loadHistory(_otherId);
    SocketService.instance.markAsRead(_otherId);
  }

  void _onTextChanged(String text) {
    SocketService.instance.sendTyping(_otherId, true);
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 1500), () {
      SocketService.instance.sendTyping(_otherId, false);
    });
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    _typingDebounce?.cancel();
    SocketService.instance.sendTyping(_otherId, false);

    SocketService.instance.sendMessage(_otherId, text);
    _input.clear();
    _jumpToBottom();
  }

  void _confirmDelete(Map<String, dynamic> msg) {
    if (msg['sender_id'] != _myId || msg['deleted'] == 1) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy Text'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: msg['text'] ?? ''));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete for Everyone', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                SocketService.instance.deleteMessage(msg['id'] as int);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    SocketService.instance.sendTyping(_otherId, false);
    _msgSub?.cancel();
    _histSub?.cancel();
    _readSub?.cancel();
    _delSub?.cancel();
    _typingSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Widget _buildStatusTicks(String? status) {
    switch (status) {
      case 'read':
        return const Icon(Icons.done_all, size: 14, color: Colors.cyanAccent);
      case 'delivered':
        return const Icon(Icons.done_all, size: 14, color: Colors.white70);
      case 'sent':
      default:
        return const Icon(Icons.done, size: 14, color: Colors.white70);
    }
  }

  Widget _buildBubble(Map<String, dynamic> m, bool isSameDayAsPrev) {
    final mine = (m['sender_id'] as int) == _myId;
    final isDeleted = m['deleted'] == 1;
    final dt = DateTime.fromMillisecondsSinceEpoch(((m['timestamp'] as int?) ?? 0) * 1000);
    final timeStr = DateFormat('h:mm a').format(dt);

    return Column(
      children: [
        if (!isSameDayAsPrev)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                DateFormat('MMMM d, y').format(dt),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: GestureDetector(
            onLongPress: () => _confirmDelete(m),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
              decoration: BoxDecoration(
                color: mine ? const Color(0xFF0F766E) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(mine ? 16 : 4),
                  bottomRight: Radius.circular(mine ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 3, offset: const Offset(0, 1)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    m['text'] ?? '',
                    style: TextStyle(
                      color: mine ? Colors.white : Colors.black87,
                      fontSize: 15,
                      fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: mine ? Colors.white70 : Colors.grey.shade600,
                        ),
                      ),
                      if (mine && !isDeleted) ...[
                        const SizedBox(width: 4),
                        _buildStatusTicks(m['status']),
                      ]
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final otherName = widget.other['display_name'] ?? widget.other['username'] ?? 'User';
    final otherCat = widget.other['category'] ?? 'A';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F4),
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: const Color(0xFF0F766E),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: otherCat == 'B' ? Colors.indigo.shade100 : Colors.teal.shade100,
              child: Text(
                otherName[0].toUpperCase(),
                style: TextStyle(color: otherCat == 'B' ? Colors.indigo.shade900 : Colors.teal.shade900, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(otherName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(
                    _otherIsTyping
                        ? 'Typing...'
                        : (otherCat == 'B' ? 'Anonymous Peer' : 'Visible Member'),
                    style: TextStyle(
                      fontSize: 11,
                      color: _otherIsTyping ? Colors.greenAccent : Colors.white70,
                      fontStyle: _otherIsTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Say hello to $otherName 👋',
                          style: const TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          bool sameDay = false;
                          if (i > 0) {
                            final prev = DateTime.fromMillisecondsSinceEpoch(
                                ((_messages[i - 1]['timestamp'] as int?) ?? 0) * 1000);
                            final curr = DateTime.fromMillisecondsSinceEpoch(
                                ((_messages[i]['timestamp'] as int?) ?? 0) * 1000);
                            sameDay = prev.year == curr.year && prev.month == curr.month && prev.day == curr.day;
                          }
                          return _buildBubble(_messages[i], sameDay);
                        },
                      ),
              ),
              if (_otherIsTyping)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(left: 16, bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F766E)),
                        ),
                        SizedBox(width: 8),
                        Text('typing...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              // Message Input Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.black12)),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _input,
                          onChanged: _onTextChanged,
                          onSubmitted: (_) => _send(),
                          maxLines: 4,
                          minLines: 1,
                          decoration: const InputDecoration(
                            hintText: 'Type a message...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send_rounded, color: Color(0xFF0F766E)),
                        onPressed: _send,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_showScrollBottom)
            Positioned(
              right: 16,
              bottom: 70,
              child: FloatingActionButton.small(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F766E),
                elevation: 3,
                onPressed: _jumpToBottom,
                child: const Icon(Icons.keyboard_arrow_down),
              ),
            ),
        ],
      ),
    );
  }
}