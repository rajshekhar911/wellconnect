import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../socket_service.dart';
import '../storage_service.dart';
import 'chat_screen.dart';
import 'login_screen.dart';

class UsersScreen extends StatefulWidget {
  final Map<String, dynamic> me;

  const UsersScreen({super.key, required this.me});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  List<Map<String, dynamic>> _users = [];
  String _searchQuery = '';
  StreamSubscription? _usersSub;
  StreamSubscription? _typingSub;
  final Map<int, bool> _typingMap = {};

  @override
  void initState() {
    super.initState();
    _usersSub = SocketService.instance.users.listen((data) {
      if (mounted) {
        setState(() {
          _users = data.map<Map<String, dynamic>>((u) => Map<String, dynamic>.from(u)).toList();
        });
      }
    });

    _typingSub = SocketService.instance.typing.listen((data) {
      final uid = data['user_id'] as int?;
      final isTyping = data['is_typing'] as bool? ?? false;
      if (mounted && uid != null) {
        setState(() {
          _typingMap[uid] = isTyping;
        });
      }
    });

    SocketService.instance.refreshUsers();
  }

  @override
  void dispose() {
    _usersSub?.cancel();
    _typingSub?.cancel();
    super.dispose();
  }

  void _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out'),
        content: Text(widget.me['category'] == 'B'
            ? 'Ensure you have copied your Recovery Key if you want to access this anonymous identity again.'
            : 'Are you sure you want to sign out?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      SocketService.instance.disconnect();
      await StorageService.clearSession();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  void _showRecoveryKeyDialog() {
    final key = widget.me['recovery_key'] ?? 'No key available';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('My Secret Key'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Keep this key safe to restore your anonymous identity on other devices:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(key, style: const TextStyle(fontFamily: 'monospace')),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: key));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                  )
                ],
              ),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  String _formatTime(int? timestamp) {
    if (timestamp == null || timestamp == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    final now = DateTime.now();
    if (now.difference(dt).inDays == 0 && now.day == dt.day) {
      return DateFormat('h:mm a').format(dt);
    } else if (now.difference(dt).inDays < 7) {
      return DateFormat('EEE').format(dt);
    }
    return DateFormat('MMM d').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAnon = widget.me['category'] == 'B';
    final myName = widget.me['display_name'] ?? widget.me['username'] ?? 'Me';

    final filteredUsers = _users.where((u) {
      final name = (u['display_name'] ?? u['username'] ?? '').toString().toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(myName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                Text(
                  isAnon ? 'Category B (Anonymous)' : 'Category A (Visible)',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (isAnon && widget.me['recovery_key'] != null)
            IconButton(
              icon: const Icon(Icons.vpn_key_outlined),
              tooltip: 'View Recovery Key',
              onPressed: _showRecoveryKeyDialog,
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: _logout,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'Search people...',
                prefixIcon: const Icon(Icons.search, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                filled: true,
                fillColor: Colors.grey.shade100,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: filteredUsers.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline, size: 54, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No contacts match "$_searchQuery"'
                                : 'No contacts available right now.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey, fontSize: 15),
                          ),
                          if (isAnon)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Note: Anonymous accounts can only view and chat with Category A accounts.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            )
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () async => SocketService.instance.refreshUsers(),
                    child: ListView.separated(
                      itemCount: filteredUsers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                      itemBuilder: (_, i) {
                        final u = filteredUsers[i];
                        final uid = u['id'] as int;
                        final isOnline = u['online'] == true;
                        final isTyping = _typingMap[uid] == true;
                        final unread = (u['unread_count'] as int?) ?? 0;
                        final lastMsg = u['last_message'] as Map<String, dynamic>?;
                        final otherCat = u['category'] ?? 'A';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: otherCat == 'B' ? Colors.indigo.shade100 : Colors.teal.shade100,
                                child: Text(
                                  (u['display_name'] ?? u['username'] ?? '?')[0].toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: otherCat == 'B' ? Colors.indigo.shade800 : Colors.teal.shade900,
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: isOnline ? Colors.green : Colors.grey.shade400,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  u['display_name'] ?? u['username'],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: otherCat == 'B' ? Colors.indigo.shade50 : Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  otherCat == 'B' ? 'Anon' : 'Visible',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: otherCat == 'B' ? Colors.indigo.shade700 : Colors.teal.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: isTyping
                              ? const Text('Typing...',
                                  style: TextStyle(color: Colors.green, fontStyle: FontStyle.italic))
                              : Text(
                                  lastMsg != null
                                      ? (lastMsg['deleted'] == 1 ? '🚫 This message was deleted' : lastMsg['text'])
                                      : (isOnline ? 'Online now' : 'Offline'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: unread > 0 ? Colors.black87 : Colors.grey.shade600,
                                    fontWeight: unread > 0 ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatTime(lastMsg != null ? lastMsg['timestamp'] : u['last_seen']),
                                style: TextStyle(fontSize: 11, color: unread > 0 ? theme.colorScheme.primary : Colors.grey),
                              ),
                              const SizedBox(height: 4),
                              if (unread > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$unread',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                )
                              else
                                const SizedBox(height: 18),
                            ],
                          ),
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(me: widget.me, other: u),
                              ),
                            );
                            SocketService.instance.refreshUsers();
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}