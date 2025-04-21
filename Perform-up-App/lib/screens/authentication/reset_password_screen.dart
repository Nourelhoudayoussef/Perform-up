import 'package:flutter/material.dart';
import 'package:pfe/controllers/signup_controller.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  _ResetPasswordScreenState createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final SignUpControllers controllers = SignUpControllers();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _codeSent = false;
  bool _isPasswordVisible = false;
  static const String baseUrl = 'http://10.0.2.2:8080';

  void _handleSendCode() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        print('Sending request to: $baseUrl/auth/forgot-password');
        print('Request body: ${jsonEncode({
          'email': controllers.emailController.text,
        })}');

        final response = await http.post(
          Uri.parse('$baseUrl/auth/forgot-password'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'email': controllers.emailController.text,
          }),
        );

        print('Response status code: ${response.statusCode}');
        print('Response body: ${response.body}');

        setState(() => _isLoading = false);

        if (response.statusCode == 200) {
          if (response.body.isNotEmpty) {
            try {
              final responseData = json.decode(response.body);
              print('Decoded response: $responseData');
            } catch (e) {
              print('Failed to decode response body: $e');
            }
          }

          setState(() => _codeSent = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Reset code sent to your email'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          String errorMessage = 'Failed to send reset code';
          if (response.body.isNotEmpty) {
            try {
              final errorData = json.decode(response.body);
              errorMessage = errorData['message'] ?? errorMessage;
            } catch (e) {
              print('Failed to decode error response: $e');
              errorMessage = 'Server error: ${response.body}';
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        print('Exception caught: $e');
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleResetPassword() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        final response = await http.post(
          Uri.parse('$baseUrl/auth/reset-password'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'email': controllers.emailController.text,
            'code': _codeController.text,
            'newPassword': _newPasswordController.text,
          }),
        );

        setState(() => _isLoading = false);

        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Password reset successfully'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacementNamed(context, '/login');
        } else {
          final errorData = json.decode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorData['message'] ?? 'Failed to reset password'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF6F9F9),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: 90),
                Text(
                  "Let's rescue your account!",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xB3000000),
                  ),
                ),
                SizedBox(height: 66),
                Center(
                  child: SvgPicture.asset(
                    'assets/images/resetPassword.svg',
                    height: 133,
                    width: 200,
                  ),
                ),
                SizedBox(height: 87),
                Text(
                  _codeSent
                      ? "Enter the verification code sent to your email"
                      : "Enter your email address to receive a password reset code",
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    color: Color(0xB3000000),
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 34),

                if (!_codeSent) ...[
                  TextFormField(
                    controller: controllers.emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: "Enter your email",
                      filled: true,
                      fillColor: Color(0xFFF0F0F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: controllers.validateEmail,
                  ),
                ] else ...[
                  TextFormField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: "Enter verification code",
                      filled: true,
                      fillColor: Color(0xFFF0F0F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter the verification code';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 20),
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: !_isPasswordVisible,
                    decoration: InputDecoration(
                      hintText: "Enter new password",
                      filled: true,
                      fillColor: Color(0xFFF0F0F0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a new password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                ],

                SizedBox(height: 40),

                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : (_codeSent ? _handleResetPassword : _handleSendCode),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6BBFB5),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                    ),
                    child: _isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text(
                            _codeSent ? 'Reset Password' : 'Send Code',
                            style: TextStyle(color: Colors.white, fontSize: 18),
                          ),
                  ),
                ),

                SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Go back to ",
                      style: GoogleFonts.pontanoSans(
                        color: Color(0xA6000000),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      child: Text(
                        "Sign in",
                        style: GoogleFonts.pontanoSans(
                          fontSize: 17,
                          color: Color(0xFF4EC1BE),
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
    );
  }
}
