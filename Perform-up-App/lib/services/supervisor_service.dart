import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class SupervisorService {
  static String baseUrl = 'http://192.168.137.209:8080';

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

  // Fetch Performance Data (GET /supervisor/performance)
  Future<Map<String, dynamic>> getPerformanceData({
    required String productRef,
    required String workshop,
    required DateTime date,
  }) async {
    final token = await _getToken();
    if (token == null) throw Exception('Not authenticated');

    final formattedDate = DateFormat('yyyy-MM-dd').format(date);
    // Remove 'Workshop ' prefix if present in the workshop parameter
    final workshopNumber = workshop.replaceAll('Workshop ', '');
    final url = Uri.parse('$baseUrl/supervisor/performance?productRef=$productRef&workshop=$workshopNumber&date=$formattedDate');
    
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    try {
      final response = await http.get(url, headers: headers);
      print('Performance data response status: ${response.statusCode}');
      print('Performance data response body: ${response.body}');

      if (response.statusCode == 200) {
        final List<dynamic> dataList = json.decode(response.body);
        // Convert list to map format
        Map<String, dynamic> formattedData = {};
        
        for (var record in dataList) {
          // Only process records that match our product reference and workshop
          if (record['orderRef'].toString() == productRef && 
              record['workshop'].toString().replaceAll('Workshop ', '') == workshopNumber) {
            
            final chain = record['chain'].toString().replaceAll('Chain ', '');
            final hour = record['hour'].toString();
            
            if (!formattedData.containsKey(chain)) {
              formattedData[chain] = {};
            }
            
            formattedData[chain][hour] = {
              'produced': record['produced']?.toString() ?? '',
              'defected': record['defectList']?[0]?['count']?.toString() ?? '0',
              'defectType': record['defectList']?[0]?['defectType']?.toString() ?? '',
            };
          }
        }
        
        print('Filtered data for product $productRef, workshop $workshopNumber: $formattedData');
        return formattedData;
      } else {
        throw Exception('Failed to fetch performance data (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      print('Error fetching performance data: $e');
      rethrow;
    }
  }
}