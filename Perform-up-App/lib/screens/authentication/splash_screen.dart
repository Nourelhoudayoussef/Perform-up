
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
//import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pfe/screens/authentication/signup_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {


  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF0F7F5),
          body: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 100),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        const SizedBox(height: 20),
                        SvgPicture.asset(
                          'assets/images/splash.svg',
                          height: 248,
                          width: 275,
                        ),
                        const SizedBox(height: 60),
                        Text(
                          "Perform Up Performance App",
                          style: GoogleFonts.poppins(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                            color: Color(0xC4000000),
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 19),
                        SizedBox(
                          width: 254,
                          height: 88,
                          child: const Text(
                            "This app helps you maximize efficiency and empower your team for more productivity and success. Together, we drive growth for the entire manufacturing process.",
                            style: TextStyle(
                                fontSize: 12,
                                color: Color(0xA5000000),
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Roboto'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 54),
                        SizedBox(
                          width: 345,
                          height: 60,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6BBFB5),
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              textStyle: const TextStyle(fontSize: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.0),
                              ),
                            ),
                            onPressed: () {
                              if (context.mounted) {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(builder: (context) => const SignUpScreen()),
                                );
                              }
                            },

                            child: const Text(
                              'Get Started',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
