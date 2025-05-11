import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SupervisorService {
  static String baseUrl = 'http://192.168.3.128:8080';

  // Get auth token from shared preferences
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // Get Daily Performance by Date
  Future<Map<String, dynamic>> getDailyPerformanceByDate(String date) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Not authenticated');

      print('DEBUG - getDailyPerformanceByDate:');
      print('Date: $date');

      final url = Uri.parse('$baseUrl/supervisor/performance/$date');
      print('Calling API: $url');
      
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final response = await http.get(
        url,
        headers: headers,
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // Handle both array and map responses
        if (data is List) {
          return {'data': data}; // Wrap array in a map
        }
        return data as Map<String, dynamic>;
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid or expired token');
      } else if (response.statusCode == 403) {
        throw Exception('Forbidden: You do not have permission to access this resource');
      } else if (response.statusCode == 404) {
        throw Exception('API endpoint not found');
      } else {
        throw Exception('Failed to get daily performance (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('Error in getDailyPerformanceByDate: $e');
      throw Exception('Failed to get daily performance: $e');
    }
  }

  // Get Performance by Workshop and Chain (Current Day)
  Future<List<Map<String, dynamic>>> getPerformanceByWorkshopChain(String workshop, String chain) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Not authenticated');

      print('DEBUG - getPerformanceByWorkshopChain:');
      print('Workshop: $workshop, Chain: $chain');

      final url = Uri.parse('$baseUrl/supervisor/performance/workshop/$workshop/chain/$chain');
      print('Calling API: $url');
      
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final response = await http.get(
        url,
        headers: headers,
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid or expired token');
      } else if (response.statusCode == 403) {
        throw Exception('Forbidden: You do not have permission to access this resource');
      } else if (response.statusCode == 404) {
        throw Exception('API endpoint not found');
      } else {
        throw Exception('Failed to get performance data (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('Error in getPerformanceByWorkshopChain: $e');
      throw Exception('Failed to get performance data: $e');
    }
  }

  // Get Performance by Date and Order Reference
  Future<Map<String, dynamic>> getPerformanceByDateAndOrder(String date, String orderRef) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Not authenticated');

      print('DEBUG - getPerformanceByDateAndOrder:');
      print('Date: $date, OrderRef: $orderRef');

      final url = Uri.parse('$baseUrl/supervisor/performance/$date/$orderRef');
      print('Calling API: $url');
      
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final response = await http.get(
        url,
        headers: headers,
      );

      print('Response status code: ${response.statusCode}');
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
        throw Exception('Failed to get performance data (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('Error in getPerformanceByDateAndOrder: $e');
      throw Exception('Failed to get performance data: $e');
    }
  }

  // Get Performance by Date, Workshop and Chain
  Future<List<Map<String, dynamic>>> getPerformanceByDateWorkshopChain(
    String date,
    String workshop,
    String chain,
  ) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Not authenticated');

      print('DEBUG - getPerformanceByDateWorkshopChain:');
      print('Date: $date, Workshop: $workshop, Chain: $chain');

      final url = Uri.parse('$baseUrl/supervisor/performance/$date/workshop/$workshop/chain/$chain');
      print('Calling API: $url');
      
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final response = await http.get(
        url,
        headers: headers,
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item)).toList();
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid or expired token');
      } else if (response.statusCode == 403) {
        throw Exception('Forbidden: You do not have permission to access this resource');
      } else if (response.statusCode == 404) {
        throw Exception('API endpoint not found');
      } else {
        throw Exception('Failed to get performance data (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('Error in getPerformanceByDateWorkshopChain: $e');
      throw Exception('Failed to get performance data: $e');
    }
  }

  // Record Performance Data
  Future<Map<String, dynamic>> recordPerformanceData(Map<String, dynamic> data) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Not authenticated');

      print('DEBUG - recordPerformanceData:');
      print('Data: $data');

      final url = Uri.parse('$baseUrl/supervisor/performance');
      print('Calling API: $url');
      
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final response = await http.post(
        url,
        headers: headers,
        body: json.encode(data),
      );

      print('Response status code: ${response.statusCode}');
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
        throw Exception('Failed to record performance data (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('Error in recordPerformanceData: $e');
      throw Exception('Failed to record performance data: $e');
    }
  }

  // Set Daily Target
  Future<Map<String, dynamic>> setDailyTarget(Map<String, dynamic> data) async {
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Not authenticated');

      print('DEBUG - setDailyTarget:');
      print('Data: $data');

      final url = Uri.parse('$baseUrl/supervisor/target');
      print('Calling API: $url');
      
      final headers = {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

      final response = await http.post(
        url,
        headers: headers,
        body: json.encode(data),
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        // Return success message in a map format
        return {'message': response.body};
      } else if (response.statusCode == 401) {
        throw Exception('Unauthorized: Invalid or expired token');
      } else if (response.statusCode == 403) {
        throw Exception('Forbidden: You do not have permission to access this resource');
      } else if (response.statusCode == 404) {
        throw Exception('API endpoint not found');
      } else {
        throw Exception('Failed to set daily target (Status: ${response.statusCode})');
      }
    } catch (e) {
      print('Error in setDailyTarget: $e');
      throw Exception('Failed to set daily target: $e');
    }
  }
} 