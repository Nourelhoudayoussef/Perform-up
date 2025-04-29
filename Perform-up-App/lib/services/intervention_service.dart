import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class InterventionService {
  // For Android Emulator use 10.0.2.2
  // For real device testing, use your computer's actual IP address
  static const String baseUrl = 'http://192.168.3.128:8080';
  // If testing on real device, comment above line and uncomment below line with your computer's IP
  // static const String baseUrl = 'http://YOUR_COMPUTER_IP:8080';

  // Get auth token from shared preferences
  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // Get technician statistics
  Future<Map<String, dynamic>> getTechnicianStats() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/api/technician/statistics'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load technician statistics');
    }
  }

  // Get recent interventions
  Future<List<Map<String, dynamic>>> getRecentInterventions() async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final response = await http.get(
      Uri.parse('$baseUrl/api/technician/interventions'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Failed to load recent interventions');
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

    final response = await http.post(
      Uri.parse('$baseUrl/api/technician/interventions'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({
        'machineReference': machineReference,
        'timeTaken': timeTaken,
        'description': description,
      }),
    );

    if (response.statusCode == 201) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to create intervention');
    }
  }
} 