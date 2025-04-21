import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:pfe/providers/notification_provider.dart';
import 'package:pfe/screens/notifications/received_notifications_view.dart';
import 'package:pfe/screens/notifications/send_notification_view.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NotificationProvider(),
      child: Scaffold(
        backgroundColor: Color(0xFFF0F7F5),
        appBar: AppBar(
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          toolbarHeight: 80,
          leading: IconButton(
            icon: const Icon(FontAwesomeIcons.arrowLeft, color: Color(0xC5000000)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            "Notifications",
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w500,
              color: Color(0xC5000000)
            ),
            
          ),
        ),
        body: Column(
          children: [
            _buildToggleButtons(),
            Expanded(
              child: Consumer<NotificationProvider>(
                builder: (context, provider, child) {
                  return provider.isReceived
                      ? ReceivedNotificationsView()
                      : SendNotificationView();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

Widget _buildToggleButtons() {
  return Consumer<NotificationProvider>(
    builder: (context, provider, child) {
      return Container(
        margin: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Color(0xFFE8F3F1),
          borderRadius: BorderRadius.circular(25),
        ),
        child: SizedBox(
          width: 280, // Set the width here
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (!provider.isReceived) provider.toggleView();
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: provider.isReceived ? Color(0xFF6BBFB5) : Colors.transparent,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      'Received',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: provider.isReceived ? Colors.white : Color(0xFF429C91),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (provider.isReceived) provider.toggleView();
                  },
                  child: Container(
                    width: 145,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: !provider.isReceived ? Color(0xFF6BBFB5) : Colors.transparent,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      'Send',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: !provider.isReceived ? Colors.white : Color(0xFF429C91),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
} 
}