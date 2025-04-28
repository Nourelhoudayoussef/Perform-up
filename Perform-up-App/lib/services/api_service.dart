import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pfe/models/chat_group.dart';
import 'package:pfe/models/message.dart';
import 'package:collection/collection.dart';
import '../models/notification_model.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

extension MapStringDynamicExtension on Map<String, dynamic> {
  // Safely get a String value from a map
  String safeString(String key, {String defaultValue = ''}) {
    final value = this[key];
    if (value == null) return defaultValue;
    return value.toString();
  }
}

class ApiService {
  // Check if running on emulator or real device and use appropriate URL
  static String get baseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8080';
    } else if (Platform.isIOS) {
      return 'http://localhost:8080';
    }
    return 'http://10.0.2.2:8080'; // Fallback
  }

  static const Duration _minRequestInterval = Duration(milliseconds: 500);
  DateTime _lastRequestTime = DateTime.now().subtract(const Duration(seconds: 1));

  Future<void> _throttleRequest() async {
    final now = DateTime.now();
    final timeSinceLastRequest = now.difference(_lastRequestTime);
    if (timeSinceLastRequest < _minRequestInterval) {
      await Future.delayed(_minRequestInterval - timeSinceLastRequest);
    }
    _lastRequestTime = DateTime.now();
  }

  Future<T> _retryRequest<T>(Future<T> Function() request) async {
    int attempts = 0;
    const maxAttempts = 3;
    Duration delay = const Duration(seconds: 1);

    while (attempts < maxAttempts) {
      try {
        await _throttleRequest();
        return await request();
      } catch (e) {
        attempts++;
        if (attempts == maxAttempts) rethrow;
        
        print('Request failed (attempt $attempts): $e');
        if (e.toString().contains('509')) {
          print('Rate limit exceeded, waiting before retry...');
          await Future.delayed(delay);
          delay *= 2; // Exponential backoff
          continue;
        }
        rethrow;
      }
    }
    throw Exception('Max retry attempts reached');
  }

  // Login method
  Future<Map<String, String>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/signin'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'email': email,
          'password': password,
        }),
      );

      print('Login response status: ${response.statusCode}'); // Debug log
      print('Login response body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token'] as String?;
        final role = data['role'] as String?;
        
        if (token == null) throw Exception('Token not found in response');
        if (role == null) throw Exception('Role not found in response');
        
        // Get user details
        final userResponse = await http.get(
          Uri.parse('$baseUrl/auth/check-user-status?email=$email'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );

        print('User details response status: ${userResponse.statusCode}'); // Debug log
        print('User details response body: ${userResponse.body}'); // Debug log

        if (userResponse.statusCode == 200) {
          final userData = json.decode(userResponse.body);
          // Try both field names for user ID
          String? userId = userData['id'] as String?;
          if (userId == null) {
            userId = userData['_id'] as String?;
          }
          final username = userData['username'] as String?;

          print('User Role: $role'); // Debug log for role
          print('User ID: $userId'); // Debug log for user ID
          print('Username: $username'); // Debug log for username

          if (userId == null) throw Exception('User ID not found');
          if (username == null) throw Exception('Username not found');

          // Store all user data in SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('token', token);
          await prefs.setString('userId', userId);
          await prefs.setString('username', username);
          await prefs.setString('email', email);
          await prefs.setString('role', role); // Store role as received from server

          return {
            'token': token,
            'userId': userId,
            'username': username,
            'role': role,
          };
        } else if (userResponse.statusCode == 403) {
          // Token might be invalid, try to clear it
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('token');
          throw Exception('Session expired. Please log in again.');
        }
        throw Exception('Failed to get user details');
      }
      
      if (response.statusCode == 403) {
        throw Exception('Authentication failed. Please check your credentials.');
      }
      
      try {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Login failed');
      } catch (e) {
        throw Exception('Login failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Login error: $e'); // Debug log
      throw Exception('Login failed: $e');
    }
  }

  // Signup method
  Future<String> signup(String email, String username, String password, String role) async {
    try {
      // If we're just resending a verification code (username and password are empty)
      if (username.isEmpty && password.isEmpty) {
        return await _resendVerificationCode(email);
      }

      // Regular signup flow
      final Map<String, String> requestBody = {
        'email': email,
        'username': username,
        'password': password,
        'role': role.toUpperCase(), // Ensure role is uppercase to match login method
      };

      print('Request body: ${json.encode(requestBody)}');

      final response = await http.post(
        Uri.parse('$baseUrl/auth/signup'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        return 'Verification code sent to your email';
      } else if (response.statusCode == 400 && response.body.contains('Email already exists')) {
        // If email exists, try to resend verification code
        return await _resendVerificationCode(email);
      } else if (response.statusCode == 403) {
        // Handle forbidden error - might be a security restriction
        return await _trySignupAsResend(email);
      } else {
        try {
          final errorData = json.decode(response.body);
          throw Exception(errorData['message'] ?? response.body);
        } catch (e) {
          throw Exception(response.body);
        }
      }
    } catch (e) {
      print('Error during signup: $e');
      throw e;
    }
  }

  // Helper method to resend verification code
  Future<String> _resendVerificationCode(String email) async {
    try {
      // Try the direct resend-verification endpoint first
      final response = await _tryResendVerification(email);
      
      // If that fails, try the signup endpoint as a fallback
      if (response == null) {
        return await _trySignupAsResend(email);
      }
      
      return response;
    } catch (e) {
      print('Error resending verification code: $e');
      throw e;
    }
  }

  // Try the dedicated resend verification endpoint
  Future<String?> _tryResendVerification(String email) async {
    try {
      final Map<String, String> requestBody = {
        'email': email,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/auth/resend-verification'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      );

      print('Resend verification response status: ${response.statusCode}');
      print('Resend verification response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final responseData = json.decode(response.body);
          return responseData['message'] ?? 'Verification code resent to your email';
        } catch (e) {
          return 'Verification code resent to your email';
        }
      } else {
        // Return null to indicate we should try the fallback method
        return null;
      }
    } catch (e) {
      print('Error with resend-verification endpoint: $e');
      return null; // Try fallback
    }
  }

  // Try using signup endpoint as a fallback for resending verification
  Future<String> _trySignupAsResend(String email) async {
    // First try with the register endpoint
    try {
      final response = await _tryEndpoint(
        '$baseUrl/auth/register', 
        email, 
        'Register'
      );
      if (response != null) return response;
    } catch (e) {
      print('Register endpoint failed, trying signup: $e');
    }
    
    // If register fails, try with signup
    try {
      final response = await _tryEndpoint(
        '$baseUrl/auth/signup', 
        email, 
        'Signup'
      );
      if (response != null) return response;
    } catch (e) {
      print('Signup endpoint failed: $e');
    }
    
    // If both fail, try with resend-verification directly
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/resend-verification'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({'email': email}),
      );
      
      print('Direct resend response: ${response.statusCode}, ${response.body}');
      
      if (response.statusCode == 200) {
        return 'Verification code resent to your email';
      }
    } catch (e) {
      print('Direct resend failed: $e');
    }
    
    // If all attempts fail
    throw Exception('Could not resend verification code. Please try again later.');
  }
  
  // Helper to try an endpoint for resending verification
  Future<String?> _tryEndpoint(String endpoint, String email, String logPrefix) async {
    final Map<String, String> requestBody = {
      'email': email,
      'username': '', // Empty to indicate this is just for resending
      'password': '', // Empty to indicate this is just for resending
      'role': 'TECHNICIAN', // Default role
    };

    final response = await http.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: json.encode(requestBody),
    );

    print('$logPrefix response status: ${response.statusCode}');
    print('$logPrefix response body: ${response.body}');

    if (response.statusCode == 200) {
      return 'Verification code sent to your email';
    } else if (response.statusCode == 400 && response.body.contains('Email already exists')) {
      return 'Verification code sent to your email';
    }
    
    return null; // Return null to indicate we should try another endpoint
  }

  // Generic GET request
  Future<dynamic> get(String endpoint) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/$endpoint'));
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load data');
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  // Generic POST request
  Future<dynamic> post(String endpoint, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(data),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to post data');
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  // Generic PUT request
  Future<dynamic> put(String endpoint, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(data),
      );
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to update data');
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  // Generic DELETE request
  Future<void> delete(String endpoint) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/$endpoint'));
      if (response.statusCode != 200) {
        throw Exception('Failed to delete data');
      }
    } catch (e) {
      throw Exception('Error: $e');
    }
  }

  // Verify email method
  Future<String> verifyEmail(String email, String code) async {
    try {
      final Map<String, String> requestBody = {
        'email': email,
        'code': code,
      };

      print('Verification request body: ${json.encode(requestBody)}'); // Debug print

      final response = await http.post(
        Uri.parse('$baseUrl/auth/verify'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      );

      print('Verification response status: ${response.statusCode}'); // Debug print
      print('Verification response body: ${response.body}'); // Debug print

      if (response.statusCode == 200) {
        try {
          final responseData = json.decode(response.body);
          return responseData['message'] ?? 'Email verified successfully';
        } catch (e) {
          return response.body;
        }
      } else {
        try {
          final errorData = json.decode(response.body);
          throw Exception(errorData['message'] ?? 'Verification failed');
        } catch (e) {
          throw Exception(response.body);
        }
      }
    } catch (e) {
      print('Error during verification: $e'); // Debug print
      throw Exception('Error during verification: $e');
    }
  }

  // Admin endpoints
  Future<List<dynamic>> getPendingUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/pending-users'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${await _getToken()}',
        },
      );
      print('Pending users response: ${response.body}'); // Debug log
      if (response.statusCode == 200) {
        return json.decode(response.body) as List<dynamic>;
      }
      throw Exception('Failed to get pending users: ${response.body}');
    } catch (e) {
      print('Error getting pending users: $e'); // Debug log
      throw Exception('Error getting pending users: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getApprovedUsers() async {
    try {
      final token = await _getToken();
      print('Getting approved users with token: ${token != null ? 'valid token' : 'no token'}');
      
      if (token == null || token.isEmpty) {
        print('Authentication token is missing or empty');
        throw Exception('Authentication required');
      }
      
      final response = await http.get(
        Uri.parse('$baseUrl/auth/approved-users'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Approved users response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        print('Successfully fetched ${data.length} approved users');
        return data.map((user) => {
          'id': user['id']?.toString() ?? user['_id']?.toString() ?? '',
          'username': user['username'],
          'email': user['email'],
        }).toList();
      } else if (response.statusCode == 403 || response.statusCode == 401) {
        print('Authentication failed (${response.statusCode}): Token may be expired');
        // Don't clear the token here to prevent logout loops
        throw Exception('Session expired. Please log in again.');
      }
      
      // Try to parse error message from response
      try {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to fetch approved users');
      } catch (e) {
        throw Exception('Failed to fetch approved users: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching approved users: $e');
      // Return empty list instead of throwing to prevent logout loops
      return [];
    }
  }

  Future<String> approveUser(String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/approve-user/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${await _getToken()}',
        },
      );
      print('Approve user response: ${response.body}'); // Debug log
      if (response.statusCode == 200) {
        return 'User approved successfully';
      }
      throw Exception('Failed to approve user: ${response.body}');
    } catch (e) {
      print('Error approving user: $e'); // Debug log
      throw Exception('Error approving user: ${e.toString()}');
    }
  }

  Future<String> deleteUser(String userId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/users/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${await _getToken()}', // Add auth header
        },
      );
      if (response.statusCode == 200) {
        return 'User deleted successfully';
      }
      throw Exception('Failed to delete user: ${response.body}');
    } catch (e) {
      throw Exception('Error deleting user: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> editProfile({
    required String email,
    String? username,
    String? currentPassword,
    String? newPassword,
    String? profilePicture,
  }) async {
    try {
      final Map<String, String> requestBody = {
        'email': email,
      };

      if (username != null && username.isNotEmpty) {
        requestBody['username'] = username;
      }

      if (currentPassword != null && newPassword != null) {
        requestBody['currentPassword'] = currentPassword;
        requestBody['newPassword'] = newPassword;
      }
      
      if (profilePicture != null && profilePicture.isNotEmpty) {
        requestBody['profilePicture'] = profilePicture;
      }

      print('Edit profile request body: ${json.encode(requestBody)}'); // Debug print

      final response = await http.put(
        Uri.parse('$baseUrl/auth/edit-profile'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer ${await _getToken()}',
        },
        body: json.encode(requestBody),
      );

      print('Edit profile response status: ${response.statusCode}'); // Debug print
      print('Edit profile response body: ${response.body}'); // Debug print

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        // Update profile picture in SharedPreferences if it was updated
        if (profilePicture != null && profilePicture.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final userId = prefs.getString('userId');
        
          // Only store the profile picture with user-specific key
          if (userId != null) {
            await prefs.setString('profilePicture_$userId', profilePicture);
            // Remove the generic key to prevent it from being shared across users
            await prefs.remove('profilePicture');
          }
        }
        
        return responseData;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to update profile');
      }
    } catch (e) {
      print('Error updating profile: $e'); // Debug print
      throw Exception('Error updating profile: $e');
    }
  }

  // Helper method to get the stored token
  Future<String?> _getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      
      print('Token retrieval - exists: ${token != null}, empty: ${token?.isEmpty ?? true}'); // Debug log
      
      if (token == null || token.isEmpty) {
        print('No valid token found in SharedPreferences'); // Debug log
        return null;
      }
      
      return token;
    } catch (e) {
      print('Error retrieving token: $e'); // Debug log
      return null;
    }
  }

  // Create a new chat group
  Future<ChatGroup> createChatGroup(String title, String creatorId, List<String> participants) async {
    return _retryRequest(() async {
      print('Starting createChatGroup - title: $title, creatorId: $creatorId'); // Debug log
      
      final token = await _getToken();
      if (token == null) {
        print('Authentication error: No valid token found'); // Debug log
        throw Exception('Authentication required - please log in again');
      }

      final requestBody = {
        'title': title,
        'creatorId': creatorId,
        'participants': participants,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/chat/groups'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(requestBody),
      );

      print('Create chat group response - Status: ${response.statusCode}'); // Debug log
      print('Response body: ${response.body}'); // Debug log

      if (response.statusCode == 200 || response.statusCode == 201) {
        return ChatGroup.fromJson(json.decode(response.body));
      }

      throw Exception('Failed to create chat group: ${response.statusCode}');
    });
  }

  // Get messages for a chat group
  Future<List<Message>> getGroupMessages(String groupId, {DateTime? since}) async {
    return _retryRequest(() async {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      String url = '$baseUrl/chat/messages/$groupId';
      if (since != null) {
        url += '?timestamp=${since.toIso8601String()}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print("Group messages fetch response status: ${response.statusCode}"); // Debug log
      print("Group messages fetch response body: ${response.body.substring(0, min(100, response.body.length))}..."); // Debug log truncated

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return []; // Return empty list for empty response
        }
        
        try {
          List<dynamic> jsonList = json.decode(response.body);
          return jsonList.map((json) => Message.fromJson(json)).toList();
        } catch (e) {
          print("Error parsing messages: $e");
          return []; // Return empty list on parse error
        }
      }
      
      // Try to parse error message from response
      if (response.body.isNotEmpty) {
        try {
          final Map<String, dynamic> errorResponse = json.decode(response.body);
          final String? errorMessage = errorResponse['message'] as String?;
          if (errorMessage != null) {
            throw Exception(errorMessage);
          }
        } catch (_) {}
      }
      
      throw Exception('Failed to fetch messages (status: ${response.statusCode})');
    });
  }

  // Send a message to a group chat
  Future<Message> sendMessage(String senderId, String chatGroupId, String content) async {
    return _retryRequest(() async {
      print("Starting to send message..."); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      print("Sending message to chat group: $chatGroupId"); // Debug log
      print("Message content: $content"); // Debug log

      // Use direct JSON string to avoid type conversion issues
      final String jsonBody = '{"senderId":"$senderId","chatGroupId":"$chatGroupId","content":"$content"}';
      print('Request body (raw): $jsonBody'); // Debug log
      
      final response = await http.post(
        Uri.parse('$baseUrl/chat/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonBody,
      );

      print("Message send response status: ${response.statusCode}"); // Debug log
      print("Message send response body: ${response.body}"); // Debug log

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.isEmpty) {
          throw Exception('Received empty response when sending message');
        }
        
        try {
          // Parse using the improved Message.fromJson
          return Message.fromJson(json.decode(response.body));
        } catch (e) {
          print("Error parsing message response: $e");
          throw Exception('Failed to parse server response: $e');
        }
      }
      
      // Try to parse error message from response
      if (response.body.isNotEmpty) {
        try {
          final Map<String, dynamic> errorResponse = json.decode(response.body);
          final String? errorMessage = errorResponse['message'] as String?;
          if (errorMessage != null) {
            throw Exception(errorMessage);
          }
        } catch (_) {}
      }
      
      throw Exception('Failed to send message (status: ${response.statusCode})');
    });
  }

  // Get all users
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    try {
      print('Getting all users...'); // Debug log
      final token = await _getToken();
      print('Using token: ${token?.substring(0, 10)}...'); // Debug log - only show first 10 chars for security

      if (token == null) {
        throw Exception('Authentication required');
      }

      // Use the approved-users endpoint which is the correct endpoint for this app
      final response = await http.get(
        Uri.parse('$baseUrl/auth/approved-users'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Get users response status: ${response.statusCode}'); // Debug log
      print('Get users response body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        final users = data.map((user) => {
          'id': user['id'] ?? user['_id'] ?? '',  // Handle both MongoDB ID formats
          'username': user['username'] ?? '',
          'email': user['email'] ?? '',
          'role': user['role'] ?? '',  // Include the role
          'profilePicture': user['profilePicture'], // Include profile picture
        }).toList();

        // Filter out admin users
        return users.where((user) => user['role']?.toString().toUpperCase() != 'ADMIN').toList();
      }
      
      // Return empty list instead of throwing exception
      print('Failed to fetch users: ${response.statusCode}');
      return [];
    } catch (e) {
      print('Error in getAllUsers: $e'); // Debug log
      // Return empty list instead of throwing
      return [];
    }
  }

  Future<List<ChatGroup>> getUserChatGroups(String userId) async {
    return _retryRequest(() async {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/chat/groups/user/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => ChatGroup.fromJson(json)).toList();
      }
      throw Exception('Failed to load chat groups: ${response.statusCode}');
    });
  }

  // Send an individual message
  Future<Message> sendIndividualMessage(String senderId, String receiverId, String content) async {
    return _retryRequest(() async {
      print("Starting to send individual message..."); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      // Ensure IDs are strings
      final String senderIdStr = senderId.toString();
      final String receiverIdStr = receiverId.toString();

      print("Sending message from: $senderIdStr to: $receiverIdStr"); // Debug log
      print("Message content: $content"); // Debug log

      // Use direct JSON string to avoid type conversion issues
      final String jsonBody = '{"senderId":"$senderIdStr","receiverId":"$receiverIdStr","content":"$content"}';
      print('Request body (raw): $jsonBody'); // Debug log
      
      final response = await http.post(
        Uri.parse('$baseUrl/chat/messages/individual'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonBody,
      );

      print("Individual message send response status: ${response.statusCode}"); // Debug log
      print("Individual message send response body: ${response.body}"); // Debug log

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (response.body.isEmpty) {
          throw Exception('Received empty response when sending message');
        }
        
        try {
          return Message.fromJson(json.decode(response.body));
        } catch (e) {
          print("Error parsing message response: $e");
          throw Exception('Failed to parse server response: $e');
        }
      } else if (response.statusCode == 403) {
        throw Exception('Authentication failed. Please check your token or login again.');
      }
      
      // Try to parse error message from response
      if (response.body.isNotEmpty) {
        try {
          final Map<String, dynamic> errorResponse = json.decode(response.body);
          final String? errorMessage = errorResponse['message'] as String?;
          if (errorMessage != null) {
            throw Exception(errorMessage);
          }
        } catch (_) {}
      }
      
      throw Exception('Failed to send message (status: ${response.statusCode})');
    });
  }

  Future<List<Message>> getIndividualMessages(String userId1, String userId2) async {
    return _retryRequest(() async {
      print("Starting to fetch individual messages..."); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      print("Fetching messages between: $userId1 and $userId2"); // Debug log

      final response = await http.get(
        Uri.parse('$baseUrl/chat/messages/individual/$userId1/$userId2'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print("Individual messages fetch response status: ${response.statusCode}"); // Debug log
      try {
        print("Individual messages fetch response body: ${response.body.substring(0, min(100, response.body.length))}..."); // Debug log truncated
      } catch (e) {
        print("Individual messages fetch response body: ${response.body}"); // Non-truncated for short messages
      }

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return []; // Return empty list for empty response
        }
        
        try {
          List<dynamic> jsonList = json.decode(response.body);
          return jsonList.map((json) => Message.fromJson(json)).toList();
        } catch (e) {
          print("Error parsing messages: $e");
          return []; // Return empty list on parse error
        }
      } else if (response.statusCode == 403) {
        throw Exception('Authentication failed. Please check your token or login again.');
      }
      
      // Try to parse error message from response
      if (response.body.isNotEmpty) {
        try {
          final Map<String, dynamic> errorResponse = json.decode(response.body);
          final String? errorMessage = errorResponse['message'] as String?;
          if (errorMessage != null) {
            throw Exception(errorMessage);
          }
        } catch (_) {}
      }
      
      throw Exception('Failed to fetch messages (status: ${response.statusCode})');
    });
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    final token = await _getToken();
    if (token == null) {
      throw Exception('No authentication token found');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/users/me'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load user data: ${response.statusCode}');
    }
  }

  // Search chat groups by name
  Future<List<ChatGroup>> searchChatGroups(String name) async {
    return _retryRequest(() async {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/chat/groups/search?name=$name'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => ChatGroup.fromJson(json)).toList();
      }
      throw Exception('Failed to search chat groups: ${response.statusCode}');
    });
  }

  // Get chat group details including members
  Future<Map<String, dynamic>> getChatGroupDetails(String groupId) async {
    return _retryRequest(() async {
      print('Getting chat group details for $groupId...'); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/chat/groups/$groupId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Get group details response status: ${response.statusCode}'); // Debug log
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Group details raw response: $data'); // Debug the full response
        
        // Extract creatorId from the group object and add it to the top level for convenience
        if (data is Map && data.containsKey('group') && data['group'] is Map) {
          final groupData = data['group'] as Map<String, dynamic>;
          if (groupData.containsKey('creatorId')) {
            // Add the creator ID at the top level for easy access
            data['creatorId'] = groupData['creatorId'].toString();
            print('Creator ID from API: ${data['creatorId']}'); // Log the creator ID
          }
        }
        
        return data;
      }
      throw Exception('Failed to get chat group details: ${response.statusCode}');
    });
  }

  Future<void> deleteChatGroup(String groupId) async {
    return _retryRequest(() async {
      print('Deleting chat group $groupId...'); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/chat/groups/$groupId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Delete group response status: ${response.statusCode}'); // Debug log
      
      if (response.statusCode != 200) {
        throw Exception('Failed to delete chat group: ${response.statusCode}');
      }
    });
  }

  // Add a member to a chat group
  Future<void> addGroupMember(String groupId, String userId) async {
    return _retryRequest(() async {
      print('Adding member $userId to group $groupId...'); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      // Use a direct JSON string to avoid any type conversion issues
      final String jsonBody = '{"userId":"$userId"}';
      print('Request body (raw): $jsonBody'); // Debug log
      
      final response = await http.post(
        Uri.parse('$baseUrl/chat/groups/$groupId/members'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonBody,
      );

      print('Add member response status: ${response.statusCode}'); // Debug log
      print('Add member response body: ${response.body}'); // Debug log
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to add member to group: ${response.statusCode} - ${response.body}');
      }
    });
  }

  // Remove a member from a chat group
  Future<void> removeGroupMember(String groupId, String userId) async {
    return _retryRequest(() async {
      print('Removing member $userId from group $groupId...'); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.delete(
        Uri.parse('$baseUrl/chat/groups/$groupId/members/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Remove member response status: ${response.statusCode}'); // Debug log
      
      if (response.statusCode != 200) {
        throw Exception('Failed to remove member from group: ${response.statusCode}');
      }
    });
  }

  // Search users by username using the new endpoint
  Future<List<Map<String, dynamic>>> searchUsers(String username) async {
    return _retryRequest(() async {
      print('Searching users with username: $username...'); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/chat/search-users?username=$username'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Search users response status: ${response.statusCode}'); // Debug log

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        return data.map((user) => {
          'id': user['id'],
          'name': user['username'],
          'email': user['email'],
          'role': user['role'],
        }).toList();
      }
      
      throw Exception('Failed to search users: ${response.statusCode}');
    });
  }
  
  // Get users that are not members of a specific group
  Future<List<Map<String, dynamic>>> getAvailableUsersForGroup(String groupId) async {
    return _retryRequest(() async {
      print('Getting available users for group: $groupId...'); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/chat/groups/$groupId/available-users'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Available users response status: ${response.statusCode}'); // Debug log

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        return data.map((user) => {
          'id': user['id'],
          'name': user['username'],
          'email': user['email'],
          'role': user['role'],
        }).toList();
      }
      
      throw Exception('Failed to get available users: ${response.statusCode}');
    });
  }
  
  // Search for users not in a group by username
  Future<List<Map<String, dynamic>>> searchAvailableUsersForGroup(String groupId, String username) async {
    return _retryRequest(() async {
      print('Searching available users for group: $groupId with username: $username...'); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final url = '$baseUrl/chat/groups/$groupId/search-users?username=$username';
      print('Making request to: $url'); // Debug log
      
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Search available users response status: ${response.statusCode}'); // Debug log
      print('Search available users response body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        print('Found ${data.length} users not in the group'); // Debug log
        
        final results = data.map((user) => {
          'id': user['id'],
          'name': user['username'],
          'email': user['email'],
          'role': user['role'],
        }).toList();
        
        print('Mapped ${results.length} user results'); // Debug log
        return results;
      }
      
      throw Exception('Failed to search available users: ${response.statusCode}');
    });
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    return _retryRequest(() async {
      print('Getting profile for user: $userId'); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/users/$userId/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Get user profile response status: ${response.statusCode}'); // Debug log
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('User profile data: $data'); // Debug log
        return data;
      } else if (response.statusCode == 404) {
        // User not found, but not an error we should crash on
        print('User profile not found for ID: $userId');
        return null;
      }
      throw Exception('Failed to get user profile: ${response.statusCode}');
    });
  }

  // Upload profile image
  Future<Map<String, dynamic>> uploadProfileImage(String userId, String imagePath) async {
    return _retryRequest(() async {
      print('Uploading profile image for user $userId from path: $imagePath'); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      // Create a multipart request
      final request = http.MultipartRequest(
        'POST', 
        Uri.parse('$baseUrl/users/$userId/profile-image')
      );

      // Add authorization header
      request.headers['Authorization'] = 'Bearer $token';

      // Add the file
      final file = await http.MultipartFile.fromPath(
        'image', 
        imagePath,
      );
      print('File name: ${file.filename}, length: ${file.length}'); // Debug log
      request.files.add(file);

      // Send the request
      print('Sending request to: ${request.url}'); // Debug log
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      print('Upload profile image response status: ${response.statusCode}'); // Debug log
      print('Upload profile image response body: ${response.body}'); // Debug log
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Try to parse the response to get the image URL
        try {
          final responseData = json.decode(response.body);
          print('Parsed response: $responseData'); // Debug log
          
          // Return the response data so the profile can be updated
          return responseData;
        } catch (e) {
          print('Error parsing response: $e'); // Debug log
          // If we can't parse the response, return a simple map with success flag
          return {'success': true};
        }
      }
      
      throw Exception('Failed to upload profile image: ${response.statusCode} - ${response.body}');
    });
  }

  Future<Map<String, dynamic>> updateUserProfile(String userId, Map<String, dynamic> profileData) async {
    return _retryRequest(() async {
      print('Updating profile for user $userId'); // Debug log
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.put(
        Uri.parse('$baseUrl/users/$userId/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode(profileData),
      );

      print('Update user profile response status: ${response.statusCode}'); // Debug log
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      }
      
      throw Exception('Failed to update user profile: ${response.statusCode}');
    });
  }

  // Get all users (both pending and approved) for admin management
  Future<List<Map<String, dynamic>>> getAllUsersForAdmin() async {
    return _retryRequest(() async {
      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/admin/all-users'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('Get all users response status: ${response.statusCode}'); // Debug log
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((user) => user as Map<String, dynamic>).toList();
      }
      
      throw Exception('Failed to get all users: ${response.statusCode}');
    });
  }

  Future<void> sendUrgentMeetingNotification(String title, String message, String senderId) async {
    try {
      print('Sending urgent meeting notification:');
      print('Title: $title');
      print('Message: $message');
      print('Sender ID: $senderId');

      final token = await _getToken();
      print('Token retrieval - exists: ${token != null}, empty: ${token?.isEmpty}');

      if (token == null) {
        throw Exception('Authentication required');
      }

      // Get current user role
      final prefs = await SharedPreferences.getInstance();
      final userRole = prefs.getString('role');
      print('Current user role: $userRole');

      final response = await http.post(
        Uri.parse('$baseUrl/notifications/urgent-meeting'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'title': title,
          'message': message,
          'senderId': senderId,
        }),
      );

      print('Urgent meeting notification response status: ${response.statusCode}');
      print('Urgent meeting notification response body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to send urgent meeting notification');
      }
    } catch (e) {
      throw Exception('Failed to send urgent meeting notification: $e');
    }
  }

  Future<List<NotificationModel>> getReceivedNotifications(String userId) async {
    await _throttleRequest();
    final token = await _getToken();
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('$baseUrl/notifications/user/$userId'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      List<dynamic> jsonResponse = json.decode(response.body);
      return jsonResponse.map((item) => NotificationModel.fromJson(item)).toList();
    } else {
      throw Exception('Failed to load notifications');
    }
  }

  Future<void> sendMachineFailureNotification(String title, String message, String senderId) async {
    try {
      print('Sending machine failure notification:');
      print('Title: $title');
      print('Message: $message');
      print('Sender ID: $senderId');

      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/notifications/machine-failure'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'title': title,
          'message': message,
          'senderId': senderId,
        }),
      );

      print('Machine failure notification response status: ${response.statusCode}');
      print('Machine failure notification response body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to send machine failure notification');
      }
    } catch (e) {
      print('Error sending machine failure notification: $e');
      throw Exception('Error sending machine failure notification: $e');
    }
  }

  Future<void> sendProductionDelayNotification(String title, String message, String senderId) async {
    try {
      print('Sending production delay notification:');
      print('Title: $title');
      print('Message: $message');
      print('Sender ID: $senderId');

      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/notifications/production-delay'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'title': title,
          'message': message,
          'senderId': senderId,
        }),
      );

      print('Production delay notification response status: ${response.statusCode}');
      print('Production delay notification response body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to send production delay notification');
      }
    } catch (e) {
      print('Error sending production delay notification: $e');
      throw Exception('Error sending production delay notification: $e');
    }
  }

  Future<void> sendEfficiencyDropNotification(String title, String message, String senderId) async {
    try {
      print('Sending efficiency drop notification:');
      print('Title: $title');
      print('Message: $message');
      print('Sender ID: $senderId');

      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/notifications/efficiency-drop'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'title': title,
          'message': message,
          'senderId': senderId,
        }),
      );

      print('Efficiency drop notification response status: ${response.statusCode}');
      print('Efficiency drop notification response body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to send efficiency drop notification');
      }
    } catch (e) {
      print('Error sending efficiency drop notification: $e');
      throw Exception('Error sending efficiency drop notification: $e');
    }
  }

  Future<void> sendEmergencyNotification(String title, String message, String senderId) async {
    try {
      print('Sending emergency notification:');
      print('Title: $title');
      print('Message: $message');
      print('Sender ID: $senderId');

      final token = await _getToken();
      if (token == null) {
        throw Exception('Authentication required');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/notifications/emergency'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'title': title,
          'message': message,
          'senderId': senderId,
        }),
      );

      print('Emergency notification response status: ${response.statusCode}');
      print('Emergency notification response body: ${response.body}');

      if (response.statusCode != 200 && response.statusCode != 201) {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to send emergency notification');
      }
    } catch (e) {
      print('Error sending emergency notification: $e');
      throw Exception('Error sending emergency notification: $e');
    }
  }

  // Notification Methods
  Future<List<NotificationModel>> getNotifications(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/notifications/$userId'),
        headers: await getHeaders(),
      );

      if (response.statusCode == 200) {
        List<dynamic> jsonList = json.decode(response.body);
        return jsonList.map((json) => NotificationModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load notifications');
      }
    } catch (e) {
      throw Exception('Error fetching notifications: $e');
    }
  }

  Future<NotificationModel> sendNotification({
    required String title,
    required String message,
    required String senderId,
    required String receiverId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/notifications/send'),
        headers: await getHeaders(),
        body: json.encode({
          'title': title,
          'message': message,
          'senderId': senderId,
          'receiverId': receiverId,
        }),
      );

      if (response.statusCode == 201) {
        return NotificationModel.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to send notification');
      }
    } catch (e) {
      throw Exception('Error sending notification: $e');
    }
  }

  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/notifications/$notificationId/read'),
        headers: await getHeaders(),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to mark notification as read');
      }
    } catch (e) {
      throw Exception('Error marking notification as read: $e');
    }
  }

  Future<Map<String, String>> getHeaders() async {
    final token = await _getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Get the last message for each conversation
  Future<Map<String, String>> getLastMessageForUsers(String currentUserId, List<String> otherUserIds) async {
    try {
      final messages = await Future.wait(otherUserIds.map((otherUserId) => getIndividualMessages(currentUserId, otherUserId)));
      final lastMessages = messages.map((messages) => messages.last.content).toList();
      return Map.fromIterables(otherUserIds, lastMessages);
    } catch (e) {
      print('Error getting last messages: $e');
      return {};
    }
  }

  // Get the last messages for multiple users efficiently
  Future<Map<String, String>> getLastMessagesForUsers(String currentUserId, List<String> userIds) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/messages/last-messages'),
        headers: await getHeaders(),
        body: json.encode({
          'currentUserId': currentUserId,
          'userIds': userIds,
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data.map((key, value) => MapEntry(key, value as String));
      } else {
        print('Failed to get last messages: ${response.statusCode}');
        return {};
      }
    } catch (e) {
      print('Error getting last messages: $e');
      return {};
    }
  }

  // Get unread message counts for all chats
  Future<Map<String, int>> getUnreadCounts(String userId) async {
    try {
      // First check if token is valid
      final token = await _getToken();
      print('Token retrieval - exists: ${token != null}, empty: ${token?.isEmpty}');
      
      if (token == null || token.isEmpty) {
        print('Authentication token is missing or empty');
        return {};
      }
      
      final response = await http.get(
        Uri.parse('$baseUrl/chat/chats/unread-counts?userId=$userId'),
        headers: await getHeaders(),
      );
  
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return data.map((key, value) => MapEntry(key, value as int));
      } else if (response.statusCode == 403) {
        print('Authentication failed (403): Token may be expired');
        // Try to refresh token or redirect to login
        return {};
      } else {
        print('Failed to get unread counts: ${response.statusCode}');
        print('Response body: ${response.body}');
        return {};  // Return empty map instead of throwing
      }
    } catch (e) {
      print('Error getting unread counts: $e');
      return {};
    }
  }

  // Mark a chat as read
  Future<void> markChatAsRead(String chatId, String userId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/chats/$chatId/read?userId=$userId'),
        headers: await getHeaders(),
      );

      if (response.statusCode != 200) {
        print('Failed to mark chat as read: ${response.statusCode}');
        print('Response body: ${response.body}');
        throw Exception('Failed to mark chat as read');
      }
    } catch (e) {
      print('Error marking chat as read: $e');
      // Silently fail to avoid breaking the UI
    }
  }

  // Get the last message for a specific user
  Future<String?> getLastMessage(String currentUserId, String otherUserId) async {
    try {
      // Get the messages for this conversation
      final messages = await getIndividualMessages(currentUserId, otherUserId);
      
      // Return the last message content if there are any messages
      if (messages.isNotEmpty) {
        final lastMessage = messages.last;
        // Truncate the message if it's too long
        if (lastMessage.content.length > 30) {
          return "${lastMessage.content.substring(0, 27)}...";
        }
        return lastMessage.content;
      }
      
      return null;
    } catch (e) {
      print('Error getting last message: $e');
      return null;
    }
  }

  // Check if token is valid and refresh if needed
 Future<bool> checkAndRefreshToken() async {
  try {
    final token = await _getToken();
    if (token == null || token.isEmpty) {
      print('No token available to check');
      return false;
    }

    // Always return true to prevent logout loops
    // This is a temporary fix until the backend issues are resolved
    print('Skipping token validation to prevent logout loops');
    return true;
  } catch (e) {
    print('Error checking token: $e');
    // Return true on error to prevent logout loops
    return true;
  }
}
}