import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import 'send_notification_view.dart';
import 'manager_notification_view.dart';
import 'received_notifications_view.dart';

enum UserRole {
  MANAGER,
  SUPERVISOR,
  TECHNICIAN
}

class RoleBasedNotificationScreen extends StatefulWidget {
  final UserRole userRole;

  const RoleBasedNotificationScreen({
    Key? key,
    required this.userRole,
  }) : super(key: key);

  @override
  _RoleBasedNotificationScreenState createState() => _RoleBasedNotificationScreenState();
}

class _RoleBasedNotificationScreenState extends State<RoleBasedNotificationScreen> {
  @override
  void initState() {
    super.initState();
    print('RoleBasedNotificationScreen initialized with role: ${widget.userRole}'); // Debug print
  }

  @override
  Widget build(BuildContext context) {
    print('Building RoleBasedNotificationScreen with role: ${widget.userRole}'); // Debug print
    return ChangeNotifierProvider(
      create: (_) {
        final provider = NotificationProvider();
        // Force set the role immediately
        provider.setRole(widget.userRole.toString().split('.').last);
        // Force technicians to received view
        if (widget.userRole == UserRole.TECHNICIAN) {
          provider.isReceived = true;
        }
        print('NotificationProvider created with role: ${provider.userRole}'); // Debug print
        return provider;
      },
      child: Scaffold(
        backgroundColor: Color(0xFFF0F7F5),
        appBar: AppBar(
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
              color: Color(0xC5000000),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(FontAwesomeIcons.solidBell, color: Color(0xC5000000)),
              onPressed: () {},
            ),
          ],
        ),
        body: Column(
          children: [
            // Only show toggle buttons for managers and supervisors
            if (widget.userRole != UserRole.TECHNICIAN) _buildToggleButtons(),
            Expanded(
              child: Consumer<NotificationProvider>(
                builder: (context, provider, child) {
                  // Technicians can only see received notifications
                  if (widget.userRole == UserRole.TECHNICIAN || provider.isReceived) {
                    return ReceivedNotificationsView();
                  } else {
                    // Show different send views based on user role
                    switch (widget.userRole) {
                      case UserRole.MANAGER:
                        return ManagerNotificationView();
                      case UserRole.SUPERVISOR:
                        return SendNotificationView();
                      case UserRole.TECHNICIAN:
                        return ReceivedNotificationsView(); // Fallback to received view
                    }
                  }
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
        // If user is a technician, only show the Received button
        if (widget.userRole == UserRole.TECHNICIAN) {
          return Container(
            margin: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(0xFFE8F3F1),
              borderRadius: BorderRadius.circular(25),
            ),
            child: SizedBox(
              width: 280,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Color(0xFF6BBFB5),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  'Received',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }

        // For managers and supervisors, show both toggles
        return Container(
          margin: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0xFFE8F3F1),
            borderRadius: BorderRadius.circular(25),
          ),
          child: SizedBox(
            width: 280,
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