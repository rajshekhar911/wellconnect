import 'dart:async';
import 'package:flutter/material.dart';
import '../socket_service.dart';
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
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = SocketService.instance.users.listen((data) {
      if (mounted) {
        setState(() => _users = data
            .map<Map<String, dynamic>>((u) => Map<String, dynamic>.from(u))
            .toList());
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _logout() {
    SocketService.instance.disconnect();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('You: ${widget.me['username']} (${widget.me['category']})'),
        actions: [
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: _users.isEmpty
          ? const Center(child: Text('No other users online yet...'))
          : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final u = _users[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(u['username'].toString()[0])),
                  title: Text(u['username']),
                  subtitle: Text('Category ${u['category']}'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(me: widget.me, other: u),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
