import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

class ApiResult {
  final bool success;
  final Map<String, dynamic>? data;
  final String? errorMessage;

  ApiResult.ok(this.data) : success = true, errorMessage = null;
  ApiResult.fail(this.errorMessage) : success = false, data = null;
}

class ApiService {
  static Future<ApiResult> registerKnown(String username, String displayName, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$serverUrl/api/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'display_name': displayName.isEmpty ? username : displayName,
          'password': password,
        }),
      ).timeout(const Duration(seconds: 10));

      final json = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return ApiResult.ok(json as Map<String, dynamic>);
      } else {
        return ApiResult.fail(json['error'] ?? 'Registration failed');
      }
    } catch (e) {
      return ApiResult.fail('Cannot connect to server at $serverUrl');
    }
  }

  static Future<ApiResult> loginKnown(String username, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$serverUrl/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      final json = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return ApiResult.ok(json as Map<String, dynamic>);
      } else {
        return ApiResult.fail(json['error'] ?? 'Login failed');
      }
    } catch (e) {
      return ApiResult.fail('Cannot connect to server at $serverUrl');
    }
  }

  static Future<ApiResult> registerAnonymous() async {
    try {
      final res = await http.post(
        Uri.parse('$serverUrl/api/register/anonymous'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      final json = jsonDecode(res.body);
      if (res.statusCode == 200 || res.statusCode == 201) {
        return ApiResult.ok(json as Map<String, dynamic>);
      } else {
        return ApiResult.fail(json['error'] ?? 'Could not create anonymous account');
      }
    } catch (e) {
      return ApiResult.fail('Cannot connect to server at $serverUrl');
    }
  }

  static Future<ApiResult> loginAnonymous(String recoveryKey) async {
    try {
      final res = await http.post(
        Uri.parse('$serverUrl/api/login/anonymous'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'recovery_key': recoveryKey}),
      ).timeout(const Duration(seconds: 10));

      final json = jsonDecode(res.body);
      if (res.statusCode == 200) {
        return ApiResult.ok(json as Map<String, dynamic>);
      } else {
        return ApiResult.fail(json['error'] ?? 'Invalid recovery key');
      }
    } catch (e) {
      return ApiResult.fail('Cannot connect to server at $serverUrl');
    }
  }

  static Future<ApiResult> verifyToken(String token) async {
    try {
      final res = await http.get(
        Uri.parse('$serverUrl/api/me'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        return ApiResult.ok(jsonDecode(res.body) as Map<String, dynamic>);
      }
      return ApiResult.fail('Session expired');
    } catch (e) {
      return ApiResult.fail('Network error');
    }
  }
}