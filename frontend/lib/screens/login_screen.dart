import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api_service.dart';
import '../storage_service.dart';
import '../socket_service.dart';
import 'users_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Category A Controllers
  final _knownUsername = TextEditingController();
  final _knownDisplayName = TextEditingController();
  final _knownPassword = TextEditingController();
  bool _isRegisteringKnown = false;
  bool _obscurePassword = true;

  // Category B Controller
  final _recoveryKeyInput = TextEditingController();
  bool _showRestoreAnonField = false;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _knownUsername.dispose();
    _knownDisplayName.dispose();
    _knownPassword.dispose();
    _recoveryKeyInput.dispose();
    super.dispose();
  }

  void _onSuccessLogin(Map<String, dynamic> session) async {
    await StorageService.saveSession(session);
    SocketService.instance.connect(session['token'] as String);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => UsersScreen(me: session)),
    );
  }

  Future<void> _submitKnown() async {
    final username = _knownUsername.text.trim();
    final password = _knownPassword.text.trim();
    final displayName = _knownDisplayName.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all required fields');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = _isRegisteringKnown
        ? await ApiService.registerKnown(username, displayName, password)
        : await ApiService.loginKnown(username, password);

    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success && result.data != null) {
      _onSuccessLogin(result.data!);
    } else {
      setState(() => _error = result.errorMessage);
    }
  }

  Future<void> _createAnonymous() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ApiService.registerAnonymous();
    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success && result.data != null) {
      final session = result.data!;
      final recKey = session['recovery_key'] ?? '';

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.shield_outlined, color: Color(0xFF0F766E)),
              SizedBox(width: 8),
              Text('Anonymous Profile', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your Alias: ${session['username']}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              const Text(
                'Save your Secret Recovery Key to re-access this profile on any device:',
                style: TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        recKey,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: recKey));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Recovery key copied to clipboard')),
                        );
                      },
                    )
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _onSuccessLogin(session);
              },
              child: const Text('Enter Chat'),
            ),
          ],
        ),
      );
    } else {
      setState(() => _error = result.errorMessage);
    }
  }

  Future<void> _restoreAnonymous() async {
    final key = _recoveryKeyInput.text.trim();
    if (key.isEmpty) {
      setState(() => _error = 'Please enter your recovery key');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await ApiService.loginAnonymous(key);
    if (!mounted) return;
    setState(() => _loading = false);

    if (result.success && result.data != null) {
      _onSuccessLogin(result.data!);
    } else {
      setState(() => _error = result.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.spa_rounded, size: 40, color: theme.colorScheme.primary),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'WellConnect',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                      ),
                      const Text(
                        'Safe, private & supportive conversations',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TabBar(
                          controller: _tabController,
                          indicator: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4, offset: const Offset(0, 2))
                            ],
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelColor: theme.colorScheme.primary,
                          unselectedLabelColor: Colors.grey.shade700,
                          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          tabs: const [
                            Tab(text: 'Known (A)'),
                            Tab(text: 'Anonymous (B)'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      SizedBox(
                        height: 260,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // TAB 1: Known User
                            Column(
                              children: [
                                TextField(
                                  controller: _knownUsername,
                                  decoration: const InputDecoration(
                                    labelText: 'Username',
                                    prefixIcon: Icon(Icons.person_outline),
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (_isRegisteringKnown) ...[
                                  TextField(
                                    controller: _knownDisplayName,
                                    decoration: const InputDecoration(
                                      labelText: 'Display Name (Optional)',
                                      prefixIcon: Icon(Icons.badge_outlined),
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                TextField(
                                  controller: _knownPassword,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                    suffixIcon: IconButton(
                                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                SizedBox(
                                  width: double.infinity,
                                  height: 46,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: theme.colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: _loading ? null : _submitKnown,
                                    child: _loading
                                        ? const SizedBox(
                                            height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : Text(_isRegisteringKnown ? 'Create Known Account' : 'Sign In'),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _isRegisteringKnown = !_isRegisteringKnown;
                                    _error = null;
                                  }),
                                  child: Text(_isRegisteringKnown
                                      ? 'Already have an account? Sign In'
                                      : 'Need an account? Register'),
                                ),
                              ],
                            ),

                            // TAB 2: Anonymous User
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text(
                                  'Your identity remains completely private. You will be assigned a permanent alias.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13, color: Colors.black87),
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  height: 46,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0284C7),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: _loading ? null : _createAnonymous,
                                    icon: const Icon(Icons.casino_outlined),
                                    label: const Text('Generate Anonymous Alias'),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (!_showRestoreAnonField)
                                  TextButton(
                                    onPressed: () => setState(() => _showRestoreAnonField = true),
                                    child: const Text('Already have a Secret Key? Restore'),
                                  )
                                else ...[
                                  TextField(
                                    controller: _recoveryKeyInput,
                                    decoration: const InputDecoration(
                                      hintText: 'Enter Secret Key (e.g. anon_...)',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: _loading ? null : _restoreAnonymous,
                                          child: const Text('Restore Session'),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close),
                                        onPressed: () => setState(() => _showRestoreAnonField = false),
                                      )
                                    ],
                                  )
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}