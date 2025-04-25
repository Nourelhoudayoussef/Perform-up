import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pfe/screens/authentication/login_screen.dart';
import 'package:pfe/screens/authentication/signup_screen.dart';
import 'package:pfe/screens/authentication/reset_password_screen.dart';
import 'package:pfe/screens/chat/ChatListScreen.dart';
import 'package:pfe/screens/home/home_screen.dart';
import 'package:pfe/screens/chat/chat_screen.dart';
import 'package:pfe/screens/admin/manage_users_screen.dart';
import 'package:pfe/screens/chat/group_chat_screen.dart';
import 'package:pfe/screens/chat/group_chats_screen.dart';
import 'package:pfe/screens/notifications/role_based_notification_screen.dart';
import 'package:pfe/screens/profile/edit_profile_screen.dart';
import 'package:pfe/services/websocket_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); 
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  initializeWebSocket();
  runApp(const MyApp());
}

// Initialize WebSocket connection if user is logged in
Future<void> initializeWebSocket() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    
    if (token != null) {
      // User is logged in, connect to WebSocket
      final webSocketService = WebSocketService();
      await webSocketService.connect();
    }
  } catch (e) {
    print('Error initializing WebSocket: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Perform Up',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6BBFB5)),
        useMaterial3: true,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignUpScreen(),
        '/reset-password': (context) => const ResetPasswordScreen(),
        '/manage-users': (context) => const ManageUsersScreen(),
        '/home': (context) => const ChatListScreen(),
        '/profile': (context) => const EditProfileScreen(),
        '/chat': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          if (args == null) {
            return const HomeScreen(); // Redirect to home if no args provided
          }
          return ChatScreen(
            userId: args['userId']?.toString() ?? '',
            username: args['username']?.toString() ?? 'Chat',
            profilePicture: args['profilePicture']?.toString(),
          );
        },
        '/group-chat': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          return GroupChatScreen(
            groupName: args?['groupName']?.toString() ?? 'Group Chat',
            groupId: args?['groupId']?.toString(),
          );
        },
        '/group-chats': (context) => const GroupChatsScreen(),
        '/notifications': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          return FutureBuilder<UserRole>(
            future: _getUserRole(args?['role']?.toString()),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              return RoleBasedNotificationScreen(
                userRole: snapshot.data ?? UserRole.TECHNICIAN,
              );
            },
          );
        },
      },
    );
  }

  Future<UserRole> _getUserRole(String? role) async {
    print('Converting role string to enum: $role'); // Debug print
    String? finalRole = role;
    
    if (finalRole == null) {
      print('Role is null, checking SharedPreferences...'); // Debug print
      final prefs = await SharedPreferences.getInstance();
      finalRole = prefs.getString('role');
      print('Role from SharedPreferences: $finalRole'); // Debug print
    }
    
    final result = switch (finalRole?.toUpperCase()) {
      'MANAGER' => UserRole.MANAGER,
      'SUPERVISOR' => UserRole.SUPERVISOR,
      'TECHNICIAN' => UserRole.TECHNICIAN,
      _ => UserRole.TECHNICIAN, // Default to technician for safety
    };
    print('Converted to UserRole: $result'); // Debug print
    return result;
  }
}
