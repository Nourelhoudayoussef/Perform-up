import 'package:flutter/material.dart';
import 'package:pfe/controllers/signup_controller.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';


class NewPasswordScreen extends StatefulWidget {
  const NewPasswordScreen({super.key});
  @override
  _NewPasswordScreenState createState() => _NewPasswordScreenState();

}

class _NewPasswordScreenState extends State<NewPasswordScreen> {
  final SignUpControllers controllers = SignUpControllers();
    final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

      bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF6F9F9), // Light background color
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
                  "Create new password",
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xB3000000),
                    
                  ),
                ),
                SizedBox(height: 66),
                Center(
                  child: SvgPicture.asset(
                    'assets/images/resetPassword.svg', // Ensure the asset is available
                    height: 133,
                    width: 200,
                  ),
                ),
                
                
                SizedBox(height: 40),


                TextFormField(
                        controller: controllers.passwordController,
                        obscureText: !_isPasswordVisible,  // Toggle visibility
                        decoration: InputDecoration(
                          hintText: 'Enter password',
                          hintStyle: GoogleFonts.pontanoSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF0F0F0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                          suffixIcon: IconButton(
                            icon: FaIcon(
                              _isPasswordVisible 
                                ? FontAwesomeIcons.eye // Icon when visible
                                : FontAwesomeIcons.eyeSlash, // Icon when hidden
                              color: Colors.grey,
                            ),
                            onPressed: () {
                              setState(() {
                                _isPasswordVisible = !_isPasswordVisible; // Toggle visibility
                              });
                            },
                          ),
                        ),
                        validator: controllers.validatePassword,
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
  controller: controllers.confirmPasswordController,
  obscureText: !_isConfirmPasswordVisible,  // Toggle visibility
  decoration: InputDecoration(
    hintText: 'Confirm password',
    hintStyle: GoogleFonts.pontanoSans(
      fontSize: 14,
      fontWeight: FontWeight.w600,
    ),
    filled: true,
    fillColor: const Color(0xFFF0F0F0),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    suffixIcon: IconButton(
      icon: FaIcon(
        _isConfirmPasswordVisible
          ? FontAwesomeIcons.eye  // Icon when visible
          : FontAwesomeIcons.eyeSlash,     // Icon when hidden
        color: Colors.grey,
      ),
      onPressed: () {
        setState(() {
          _isConfirmPasswordVisible = !_isConfirmPasswordVisible; // Toggle visibility
        });
      },
    ),
  ),
  validator: controllers.validateConfirmPassword,
),


                SizedBox(height: 70),

                
                SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          Navigator.pushNamed(context, '/login');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6BBFB5),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.0),
                        ),
                      ),
                      child: const Text(
                        'Go Back',
                        style: TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ),
                  ),
                
              ],
            ),
          ),
        ),
      ),
    );
  }
}