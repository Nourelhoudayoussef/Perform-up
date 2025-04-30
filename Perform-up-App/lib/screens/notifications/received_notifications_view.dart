import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../../providers/notification_provider.dart';
import '../../services/websocket_service.dart';
import '../../models/notification_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class ReceivedNotificationsView extends StatefulWidget {
  const ReceivedNotificationsView({super.key});

  @override
  _ReceivedNotificationsViewState createState() => _ReceivedNotificationsViewState();
}

class _ReceivedNotificationsViewState extends State<ReceivedNotificationsView> {
  bool _isLoading = true;
  String? _error;
  final WebSocketService _webSocketService = WebSocketService();
  StreamSubscription? _notificationSubscription;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeToWebSocketNotifications();
  }
  
  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }
  
  // Subscribe to WebSocket notifications
  void _subscribeToWebSocketNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    
    if (userId == null) {
      print('Error: User ID not found in SharedPreferences');
      return;
    }

    // Connect to websocket if not already connected
    if (!_webSocketService.isConnected) {
      await _webSocketService.connect();
    }

    // Subscribe to notifications
    _webSocketService.subscribeToNotifications(userId);

    _notificationSubscription = _webSocketService.notificationStream.listen((notification) {
      // Add the notification to the provider
      final provider = Provider.of<NotificationProvider>(context, listen: false);
      provider.addNewNotification(notification);
    });
  }

  Future<void> _loadNotifications() async {
    try {
      await Provider.of<NotificationProvider>(context, listen: false).loadReceivedNotifications();
      
      // Connect to websocket if not already connected
      if (!_webSocketService.isConnected) {
        await _webSocketService.connect();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
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
    return Consumer<NotificationProvider>(
      builder: (context, provider, child) {
        if (_isLoading) {
          return Center(
            child: CircularProgressIndicator(
              color: Color(0xFF6BBFB5),
            ),
          );
        }

        if (_error != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Error loading notifications',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
                SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _isLoading = true;
                    });
                    _loadNotifications();
                  },
                  child: Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (provider.receivedNotifications.isEmpty) {
          return Center(
            child: Text(
              'No notifications yet',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _loadNotifications,
          color: Color(0xFF6BBFB5),
          child: ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: provider.receivedNotifications.length,
            itemBuilder: (context, index) {
              final notification = provider.receivedNotifications[index];
              return Container(
                margin: EdgeInsets.only(bottom: 16),
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: notification.senderProfilePicture != null && notification.senderProfilePicture!.isNotEmpty
                          ? (notification.senderProfilePicture!.startsWith('data:image')
                              ? MemoryImage(
                                  base64Decode(
                                    notification.senderProfilePicture!.split(',').last,
                                  ),
                                )
                              : NetworkImage(notification.senderProfilePicture!)
                            ) as ImageProvider
                          : AssetImage('assets/images/avatar.jpg'),
                      radius: 25,
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  notification.title,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xC5000000),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                notification.createdAt.toString(),
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Color(0x61000000),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            notification.message,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Color(0x99000000),
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Type: ${notification.type}',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Color(0x61000000),
                            ),
                          ),
                          if (notification.senderId != null) ...[
                            SizedBox(height: 4),
                            Text(
                              'From: ${notification.senderId}',
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Color(0x99000000),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
} 