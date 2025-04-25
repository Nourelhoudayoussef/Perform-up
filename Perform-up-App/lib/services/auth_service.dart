// lib/services/auth_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'websocket_service.dart';

class AuthService {
  static const String baseUrl = 'http://10.0.2.2:8080'; // Android emulator localhost

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'username': name,
          'password': password,
          'role': role,
        }),
      );

      print('Signup Response: ${response.body}');
      print('Signup Status Code: ${response.statusCode}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData is String ? errorData : errorData['message'] ?? 'Signup failed');
      }
    } catch (e) {
      print('Signup error: $e');
      throw Exception('Error during signup: $e');
    }
  }

  Future<bool> verifyOtp({
    required String email,
    required String code,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'code': code,
        }),
      );

      print('Verify Response: ${response.body}');
      print('Verify Status Code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return responseData['message'] == 'Email verified successfully';
      }
      final errorData = json.decode(response.body);
      throw Exception(errorData is String ? errorData : errorData['message'] ?? 'Verification failed');
    } catch (e) {
      print('Verify error: $e');
      throw Exception('Error during verification: $e');
    }
  }
  
  // Connect to WebSocket after successful login
  Future<void> connectWebSocket() async {
    try {
      final webSocketService = WebSocketService();
      await webSocketService.connect();
    } catch (e) {
      print('Error connecting to WebSocket: $e');
    }
  }
  
  // Disconnect from WebSocket on logout
  Future<bool> logout() async {
    try {
      // Disconnect from WebSocket
      final webSocketService = WebSocketService();
      webSocketService.disconnect();
      
      // Clear stored credentials
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('userId');
      await prefs.remove('username');
      await prefs.remove('email');
      await prefs.remove('role');
      
      return true;
    } catch (e) {
      print('Error during logout: $e');
      return false;
    }
  }
}
