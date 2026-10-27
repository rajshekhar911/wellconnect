import 'package:flutter/material.dart';
import 'storage_service.dart';
import 'socket_service.dart';
import 'screens/login_screen.dart';
import 'screens/users_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await StorageService.getSession();
  runApp(WellConnectApp(initialSession: session));
}

class WellConnectApp extends StatelessWidget {
  final Map<String, dynamic>? initialSession;

  const WellConnectApp({super.key, this.initialSession});

  @override
  Widget build(BuildContext context) {
    if (initialSession != null && initialSession!['token'] != null) {
      SocketService.instance.connect(initialSession!['token'] as String);
    }

    return MaterialApp(
      title: 'WellConnect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          primary: const Color(0xFF0F766E),
          secondary: const Color(0xFF0284C7),
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: initialSession != null
          ? UsersScreen(me: initialSession!)
          : const LoginScreen(),
    );
  }
}