import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SupervisorService {
  static String baseUrl = 'http://192.168.3.128:8080';

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // Set Daily Target (POST /supervisor/target?orderRef=...&target=...)
  Future<String> setDailyTarget(int orderRef, int target) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');
    final url = Uri.parse('$baseUrl/supervisor/target?orderRef=$orderRef&target=$target');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final response = await http.post(url, headers: headers);
    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to set daily target (${response.statusCode}): ${response.body}');
    }
  }

  // Record Performance Data (POST /supervisor/performance)
  Future<String> recordPerformanceData(Map<String, dynamic> data) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');
    final url = Uri.parse('$baseUrl/supervisor/performance');
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    final response = await http.post(
      url,
      headers: headers,
      body: json.encode(data),
    );
    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw Exception('Failed to record performance data (${response.statusCode}): ${response.body}');
    }
  }
}