import 'package:flutter/material.dart';
import '../api_service.dart';
import '../socket_service.dart';
import 'users_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _category = 'A';
  final _username = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ApiService.login(_category, _username.text.trim());
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _loading = false;
        _error = 'Login failed. Make sure the server is running.';
      });
      return;
    }
    SocketService.instance.connect(result['token'] as String);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => UsersScreen(me: result)),
    );
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat App')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Select your category',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('A - Visible'),
                  selected: _category == 'A',
                  onSelected: (_) => setState(() => _category = 'A'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('B - Anonymous'),
                  selected: _category == 'B',
                  onSelected: (_) => setState(() => _category = 'B'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_category == 'A')
              TextField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              )
            else
              const Text('You will get a random anonymous name.'),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
            ],
            ElevatedButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Enter Chat'),
            ),
          ],
        ),
      ),
    );
  }
}
