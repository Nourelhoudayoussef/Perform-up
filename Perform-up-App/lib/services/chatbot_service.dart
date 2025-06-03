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
      final userId = prefs.getString('userId'); // Get user ID from shared preferences
      
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
          'user_id': userId ?? 'anonymous', // Include user ID in the request
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

  Future<List<Map<String, dynamic>>> getChatHistory() async {
    try {
      // Get the authentication token and user ID
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final userId = prefs.getString('userId');
      
      if (token == null) {
        throw Exception('Authentication required');
      }
      
      if (userId == null || userId.isEmpty) {
        throw Exception('User ID not found');
      }
      
      print('Getting chat history for user: $userId');
      
      // Try both approaches to maximize chances of success
      // 1. First try the direct Flask endpoint with the MongoDB ID
      try {
        final directResponse = await http.get(
          Uri.parse('http://192.168.137.209:5001/chatbot/history/$userId'),
          headers: {
            'Content-Type': 'application/json',
          },
        );
        
        if (directResponse.statusCode == 200) {
          final data = json.decode(directResponse.body);
          print('Direct Flask response status: ${data['status']}');
          print('Conversation count: ${data['count']}');
          if (data['server_time'] != null) {
            print('Server time: ${data['server_time']}');
          }
          
          if (data['status'] == 'success' && data['conversations'] != null) {
            print('Successfully retrieved chat history directly from Flask');
            final conversations = List<Map<String, dynamic>>.from(data['conversations']);
            if (conversations.isNotEmpty) {
              print('First conversation timestamp: ${conversations[0]['timestamp']}');
            }
            return conversations;
          }
        }
      } catch (e) {
        print('Error with direct Flask call: $e');
        // Continue to try the Spring Boot approach
      }
      
      // 2. Fallback to the Spring Boot endpoint if direct approach fails
      final response = await http.get(
        Uri.parse('${ConfigService.baseUrl}/api/chatbot/history'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Spring Boot response: ${data['status']}');
        
        if (data['status'] == 'success' && data['conversations'] != null) {
          final conversations = List<Map<String, dynamic>>.from(data['conversations']);
          if (conversations.isNotEmpty) {
            print('First conversation timestamp from Spring Boot: ${conversations[0]['timestamp']}');
          }
          return conversations;
        }
        return [];
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception('Authentication error. Please log in again.');
      } else {
        print('Chat history error: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to fetch chat history');
      }
    } catch (e) {
      print('Chat history error: $e');
      throw Exception('Error fetching chat history: $e');
    }
  }
} 