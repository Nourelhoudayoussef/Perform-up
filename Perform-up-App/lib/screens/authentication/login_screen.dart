import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pfe/controllers/signup_controller.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:pfe/services/api_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  final SignUpControllers controllers = SignUpControllers();
  bool _isLoginPasswordVisible = false;
  static const String baseUrl = 'http://10.0.2.2:8080'; // Android emulator localhost

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      print('Attempting login for user: $email');

      final response = await http.post(
        Uri.parse('$baseUrl/auth/signin'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      print('Response status: ${response.statusCode}'); // Debug log
      print('Response body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token'];
        final role = data['role'];

        // Store the token and user info for future use
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        await prefs.setString('email', email);
        await prefs.setString('role', role.toUpperCase()); // Store role in uppercase
        print('Stored role in SharedPreferences: ${role.toUpperCase()}'); // Debug print

        // Get user details to retrieve the userId
        try {
          final userResponse = await http.get(
            Uri.parse('$baseUrl/auth/check-user-status?email=$email'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
          );

          print('User details response status: ${userResponse.statusCode}'); // Debug log
          print('User details response body: ${userResponse.body}'); // Debug log

          if (userResponse.statusCode == 200) {
            final userData = json.decode(userResponse.body);
            
            // Handle both 'id' and '_id' field names for MongoDB compatibility
            String? userId = userData['id'];
            if (userId == null) {
              userId = userData['_id'];
            }
            
            final username = userData['username'];

            // Store user ID and username
            if (userId != null) {
              await prefs.setString('userId', userId.toString()); // Convert to string in case it's an ObjectId
              print('Stored userId: $userId'); // Debug log
            } else {
              print('WARNING: User ID not found in response!');
            }
            
            await prefs.setString('username', username);
            print('Stored username: $username'); // Debug log
            
            // Print all stored preferences for debugging
            print('DEBUG - All stored preferences:');
            print('token: ${prefs.getString('token') != null ? 'exists' : 'missing'}');
            print('email: ${prefs.getString('email')}');
            print('role: ${prefs.getString('role')}');
            print('userId: ${prefs.getString('userId')}');
            print('username: ${prefs.getString('username')}');
          } else {
            print('Failed to get user details: ${userResponse.statusCode}');
            // Continue anyway, as we have the token and role
          }
        } catch (e) {
          print('Error getting user details: $e');
          // Continue anyway, as we have the token and role
        }
        
        print('Login successful');
        print('Role from server: $role'); // Debug print

        if (mounted) {
          if (role.toUpperCase() == 'ADMIN') {
            Navigator.pushReplacementNamed(context, '/manage-users');
          } else {
            Navigator.pushReplacementNamed(context, '/home');
          }
        }
      } else {
        if (mounted) {  // Check if widget is still mounted
          String errorMessage;
          try {
            // Try to parse the error response
            final errorData = json.decode(response.body);
            errorMessage = errorData is String ? errorData : (errorData['message'] ?? 'Login failed');
            print('Error message from server: $errorMessage'); // Add this debug log
          } catch (e) {
            // If response body is empty or not JSON, use status code
            errorMessage = 'Login failed with status code: ${response.statusCode}';
            print('Error parsing response: $e'); // Add this debug log
            print('Response body: ${response.body}'); // Add this to see raw response
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Login error: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
        
        // Show error message to the user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F5),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 100),

                  Center(
                    child: Text(
                      "Welcome Back!",
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),

                  const SizedBox(height: 33),

                  Center(
                    child: SvgPicture.asset(
                      'assets/images/login.svg', // Ensure the asset is available
                      height: 188,
                      width: 188,
                    ),
                  ),

                  const SizedBox(height: 33),

                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      hintText: 'Enter your email',
                      filled: true,
                      fillColor: const Color(0xFFF0F0F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.0),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                    ),
                    validator: controllers.validateEmail,
                  ),

                  const SizedBox(height: 20),

                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isLoginPasswordVisible,
                    decoration: InputDecoration(
                      hintText: 'Enter your password',
                      filled: true,
                      fillColor: const Color(0xFFF0F0F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10.0),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      suffixIcon: IconButton(
                        icon: FaIcon(
                          _isLoginPasswordVisible
                            ? FontAwesomeIcons.eye  // Icon when visible
                            : FontAwesomeIcons.eyeSlash,     // Icon when hidden
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _isLoginPasswordVisible = !_isLoginPasswordVisible; // Toggle visibility
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 5),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/reset');
                        },
                        child: const Text(
                          'Forgot Password?',
                          style: TextStyle(color: Colors.black54),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6BBFB5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                      ),
                      onPressed: _isLoading
    ? null
    : () async {
        setState(() => _isLoading = true);

        try {
          final result = await ApiService().login(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );

          final role = result['role'];

          // ✅ Log the token to make sure it's saved correctly
          final prefs = await SharedPreferences.getInstance();
          final storedToken = prefs.getString('token');
          print('✅ TOKEN STORED AFTER LOGIN: $storedToken');

          if (!mounted) return;

          if (role != null && role.toUpperCase() == 'ADMIN') {
            Navigator.pushReplacementNamed(context, '/manage-users');
          } else {
            Navigator.pushReplacementNamed(context, '/home');
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  e.toString().replaceAll('Exception: ', ''),
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
      },
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Sign In',
                              style: TextStyle(color: Colors.white, fontSize: 16),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account? "),
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/signup');
                        },
                        child: const Text(
                          'Sign up',
                          style: TextStyle(
                            color: Color(0xFF6BBFB5),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
