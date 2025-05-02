import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

class InterventionService {
  // Use the same dynamic base URL approach as ApiService
  static String get baseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8080';
    } else if (Platform.isIOS) {
      return 'http://localhost:8080';
    }
    return 'http://10.0.2.2:8080'; // Fallback
  }

  // Get auth token from shared preferences
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // Get technician statistics
  Future<Map<String, dynamic>> getTechnicianStats() async {
    try {
      final token = await _getToken();
      print('DEBUG - getTechnicianStats:');
      print('Token retrieved: ${token != null ? 'Yes (${token.substring(0, 10)}...)' : 'No'}');

      if (token == null) throw Exception('Not authenticated');

      // Get and print role for debugging
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('role');
      print('Current user role: $role');

      final url = Uri.parse('$baseUrl/technician/statistics');
      print('Calling API: $url');
      print('Request headers:');
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      print(headers);

      final response = await http.get(
        url,
        headers: headers,
      );

      print('Response status code: ${response.statusCode}');
      print('Response headers: ${response.headers}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid or expired token');
      } else if (response.statusCode == 403) {
        throw Exception('Forbidden: You do not have permission to access this resource');
      } else if (response.statusCode == 404) {
        throw Exception('API endpoint not found');
      } else {
        throw Exception('Failed to load technician statistics (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('Error in getTechnicianStats: $e');
      throw Exception('Failed to load technician statistics: $e');
    }
  }

  // Get recent interventions
  Future<List<Map<String, dynamic>>> getRecentInterventions() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    print('DEBUG - getRecentInterventions:');
    print('Token retrieved: ${token != null ? 'Yes (${token.substring(0, 10)}...)' : 'No'}');

    final url = Uri.parse('$baseUrl/technician/interventions');
    print('Calling API: $url');
    
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    print('Request headers:');
    print(headers);

    final response = await http.get(
      url,
      headers: headers,
    );

    print('Response status code: ${response.statusCode}');
    print('Response headers: ${response.headers}');
    print('Response body: ${response.body}');

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      print('DEBUG - Raw intervention data:');
      print(data);
      
      // Convert the raw data and ensure all fields are properly typed
      return data.map<Map<String, dynamic>>((item) {
        print('DEBUG - Processing intervention item:');
        print(item);
        
        // Try to get time taken from various possible field names
        final timeTaken = item['timeSpent'] ?? 0;
                         
        return {
          'machineReference': item['machineReference'] ?? '',
          'timeTaken': timeTaken,
          'description': item['description'] ?? '',
          'date': item['date'] ?? DateTime.now().toIso8601String().split('T')[0],
        };
      }).toList();
    } else if (response.statusCode == 401) {
      throw Exception('Unauthorized: Invalid or expired token');
    } else if (response.statusCode == 403) {
      throw Exception('Forbidden: You do not have permission to access this resource');
    } else if (response.statusCode == 404) {
      throw Exception('API endpoint not found');
    } else {
      throw Exception('Failed to load recent interventions (Status: ${response.statusCode})');
    }
  }

  // Create new intervention
  Future<Map<String, dynamic>> createIntervention({
    required String machineReference,
    required int timeTaken,
    required String description,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    print('DEBUG - createIntervention:');
    print('Token retrieved: ${token != null ? 'Yes (${token.substring(0, 10)}...)' : 'No'}');

    final url = Uri.parse('$baseUrl/technician/intervention');
    print('Calling API: $url');
    
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    print('Request headers:');
    print(headers);

    final body = json.encode({
      'machineReference': machineReference,
      'timeTaken': timeTaken,
      'description': description,
      'date': DateTime.now().toIso8601String().split('T')[0], // Add current date in yyyy-MM-dd format
    });
    print('Request body:');
    print(body);

    final response = await http.post(
      url,
      headers: headers,
      body: body,
    );

    print('Response status code: ${response.statusCode}');
    print('Response headers: ${response.headers}');
    print('Response body: ${response.body}');

    if (response.statusCode == 201 || response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 401) {
      throw Exception('Unauthorized: Invalid or expired token');
    } else if (response.statusCode == 403) {
      throw Exception('Forbidden: You do not have permission to access this resource');
    } else if (response.statusCode == 404) {
      throw Exception('API endpoint not found');
    } else {
      throw Exception('Failed to create intervention (Status: ${response.statusCode})');
    }
  }
} 