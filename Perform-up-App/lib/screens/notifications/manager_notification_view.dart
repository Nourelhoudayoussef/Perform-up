import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/notification_provider.dart';

class ManagerNotificationView extends StatefulWidget {
  const ManagerNotificationView({super.key});

  @override
  _ManagerNotificationViewState createState() => _ManagerNotificationViewState();
}

class _ManagerNotificationViewState extends State<ManagerNotificationView> {
  bool _isLoading = false;
  String? _currentRole;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    print('Current role from SharedPreferences: $role'); // Debug print
    if (mounted) {
      setState(() {
        _currentRole = role;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, provider, child) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Alert Type Section
              Text(
                'Alert Type:',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xC5000000),
                ),
              ),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(FontAwesomeIcons.circleInfo, 
                      size: 16, 
                      color: Color(0xC5000000)
                    ),
                    SizedBox(width: 12),
                    Text(
                      "Urgent Meeting Alert",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Color(0xC5000000),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),

              // Send to Section
              Text(
                'Send to:',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xC5000000),
                ),
              ),
              SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(FontAwesomeIcons.circleInfo, 
                      size: 16, 
                      color: Color(0xC5000000)
                    ),
                    SizedBox(width: 12),
                    Text(
                      "Managers and supervisors",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Color(0xC5000000),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 32),

              // Send Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: provider.canSendNotifications && !_isLoading ? () async {
                    setState(() {
                      _isLoading = true;
                    });
                    
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      final senderId = prefs.getString('userId');
                      if (senderId == null) throw Exception('User ID not found');

                      // Send urgent meeting notification
                      await provider.sendUrgentMeetingNotification(
                        "Urgent Meeting Call",
                        "Please join the urgent meeting immediately",
                        senderId,
                      );
                      
                      // Show success message
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Urgent meeting notification sent successfully'),
                            backgroundColor: Color(0xFF6BBFB5),
                          ),
                        );
                      }
                    } catch (e) {
                      // Show error message
                      if (context.mounted) {
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
                  } : null, // Disable button if user can't send notifications
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF6BBFB5),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: _isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          provider.canSendNotifications ? 'Send' : 'No Permission to Send',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
} 