import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class ApiService {
  static Future<Map<String, dynamic>?> login(String category, String username) async {
    try {
      final res = await http.post(
        Uri.parse('$serverUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'category': category, 'username': username}),
      );
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // server unreachable
    }
    return null;
  }
}
