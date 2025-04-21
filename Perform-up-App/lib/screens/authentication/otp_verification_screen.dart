import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pfe/services/api_service.dart';

class OtpVerificationScreen extends StatefulWidget {
  final String email;

  const OtpVerificationScreen({super.key, required this.email});

  @override
  _OtpVerificationScreenState createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  TextEditingController otpController = TextEditingController();
  bool isOtpValid = false;
  bool _isLoading = false;
  final _apiService = ApiService();

  void verifyOtp() async {
    String enteredOtp = otpController.text.trim();
    if (enteredOtp.length == 6) {
      setState(() => _isLoading = true);
      
      try {
        String message = await _apiService.verifyEmail(
          widget.email,
          enteredOtp,
        );

        setState(() => _isLoading = false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
      } catch (e) {
        setState(() => _isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter a valid 6-digit code"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void resendOtp() async {
    setState(() => _isLoading = true);
    
    try {
      String message = await _apiService.signup(
        widget.email,
        '', // Not needed for resend
        '', // Not needed for resend
        'TECHNICIAN', // Default role
      );

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F5),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Verify Code",
                style: GoogleFonts.poppins(
                  fontSize: 21,
                  fontWeight: FontWeight.w500,
                  color: Color(0xC4000000)
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Enter the verification code sent to",
                style: GoogleFonts.pontanoSans(
                  fontSize: 14,
                  color: Color(0xA6000000),
                ),
                textAlign: TextAlign.center,
              ),
              Text(
                widget.email,
                style: GoogleFonts.pontanoSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xA6000000),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              // Custom OTP input implementation
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) => _buildOtpDigitField(index)),
              ),
              const SizedBox(height: 30),
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
                  onPressed: _isLoading ? null : verifyOtp,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Verify',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
                ),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: _isLoading ? null : resendOtp,
                child: Text(
                  "Resend Code",
                  style: TextStyle(
                    color: Color(0xFF6BBFB5),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Build a single OTP digit input field
  Widget _buildOtpDigitField(int index) {
    return Container(
      width: 40,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: isOtpValid ? const Color(0xFF6BBFB5) : Colors.grey,
          width: 1.5,
        ),
      ),
      child: TextField(
        onChanged: (value) {
          if (value.length == 1) {
            // Auto-focus to next field
            if (index < 5) {
              FocusScope.of(context).nextFocus();
            } else {
              FocusScope.of(context).unfocus();
            }
            
            // Update the OTP value
            final newOtp = otpController.text.padRight(index, '0').substring(0, index) + 
                          value + 
                          (index < 5 ? otpController.text.substring(index + 1) : '');
            
            otpController.text = newOtp;
            setState(() {
              isOtpValid = otpController.text.length == 6;
            });
          } else if (value.isEmpty) {
            // Auto-focus to previous field
            if (index > 0) {
              FocusScope.of(context).previousFocus();
            }
            
            // Update the OTP value
            final newOtp = otpController.text.substring(0, index) + 
                          ' ' + 
                          (index < 5 ? otpController.text.substring(index + 1) : '');
            
            otpController.text = newOtp;
            setState(() {
              isOtpValid = false;
            });
          }
        },
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        decoration: const InputDecoration(
          counterText: '',
          border: InputBorder.none,
        ),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
