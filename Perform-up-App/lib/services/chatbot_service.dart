import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config_service.dart';

class ChatbotService {
  static final ChatbotService _instance = ChatbotService._internal();
  factory ChatbotService() => _instance;
  
  ChatbotService._internal();
  
  Future<String> sendMessage(String message) async {
    try {
      // Get the authentication token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      
      if (token == null) {
        return 'You need to be logged in to use the chatbot.';
      }
      
      // Using the proxy approach through Spring Boot backend
      final response = await http.post(
        Uri.parse('${ConfigService.baseUrl}/api/chatbot'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'message': message,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['response'] ?? 'No response from chatbot';
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return 'Authentication error. Please log in again.';
      } else {
        print('Chatbot error: ${response.statusCode} - ${response.body}');
        return 'Error: Failed to get a response from the chatbot.';
      }
    } catch (e) {
      print('Chatbot error: $e');
      return 'Error communicating with chatbot service. Please try again later.';
    }
  }
  
  Future<bool> checkChatbotStatus() async {
    try {
      final response = await http.get(
        Uri.parse('${ConfigService.baseUrl}/api/chatbot/diagnostics'),
      );
      
      return response.statusCode == 200;
    } catch (e) {
      print('Chatbot status check error: $e');
      return false;
    }
  }
} 