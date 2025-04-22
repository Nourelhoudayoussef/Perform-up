import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pfe/screens/chat/chat_screen.dart';
import 'package:pfe/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // Add this import for Timer
import 'dart:convert'; // Add this import for base64Decode

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  _ChatListScreenState createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> users = [];
  bool isLoading = true;
  String searchQuery = "";
  Map<String, int> unreadCounts = {}; // Store unread counts for each chat
  Map<String, String> lastMessages = {}; // Store last messages for each user
  String? currentUserId; // Store current user ID
  Timer? _timer; // Timer to refresh unread counts

  @override
  void initState() {
    super.initState();
    _checkTokenOnHome();
    _loadData();
  }
  void _checkTokenOnHome() async {
  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString('token');
  print('TOKEN WHEN ENTERING HOME: $token');}

  Future<void> _loadData() async {
  setState(() {
    isLoading = true;
  });

  try {
    final prefs = await SharedPreferences.getInstance();
    currentUserId = prefs.getString('userId');
    
    if (currentUserId != null) {
      // Skip token validation to prevent logout loops
      // This is a temporary fix until backend issues are resolved
      
      // Load data in parallel for better performance
      try {
        final futures = await Future.wait([
          _apiService.getAllUsers(),
          _apiService.getUnreadCounts(currentUserId!),
        ]);

        final allUsers = futures[0] as List<Map<String, dynamic>>;
        final unreadCountsData = futures[1] as Map<String, int>;

        // Filter out current user and admin users
        final filteredUsers = allUsers.where((user) => 
          user['id'] != null && 
          user['id'].toString() != currentUserId &&
          user['role']?.toString().toUpperCase() != 'ADMIN'
        ).toList();

        // Get all user IDs for last messages query
        final userIds = filteredUsers.map((user) => user['id'].toString()).toList();
        
        // Get last messages for all users in a single call
        final lastMessagesData = await _apiService.getLastMessagesForUsers(
          currentUserId!, 
          userIds
        );

        if (mounted) {
          setState(() {
            users = filteredUsers;
            unreadCounts = unreadCountsData;
            lastMessages = lastMessagesData;
            isLoading = false;
          });
        }
      } catch (e) {
        print('Error loading user data: $e');
        // Don't redirect to login, just show empty state
        if (mounted) {
          setState(() {
            users = [];
            isLoading = false;
          });
        }
      }
    } else {
      print('No user ID found, but not redirecting to login');
      // Don't redirect to login, just show empty state
      if (mounted) {
        setState(() {
          users = [];
          isLoading = false;
        });
      }
    }
  } catch (e) {
    print('Error in _loadData: $e');
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }
}

  Future<void> _loadUnreadCounts() async {
    try {
      if (currentUserId != null) {
        final newUnreadCounts = await _apiService.getUnreadCounts(currentUserId!);
        if (mounted) {
          setState(() {
            unreadCounts = newUnreadCounts;
          });
        }
      }
    } catch (e) {
      print('Error loading unread counts: $e'); // Debug print
    }
  }

  // Generate individual chat ID (same logic as in backend)
  String _generateChatId(String userId1, String userId2) {
    // Sort the IDs to ensure consistency
    List<String> ids = [userId1, userId2];
    ids.sort();
    return "individual_${ids[0]}_${ids[1]}";
  }

  // Get unread count for a specific user
  int _getUnreadCount(String userId) {
    if (currentUserId == null) return 0;
    
    // Generate the chat ID for this user pair
    String chatId = _generateChatId(currentUserId!, userId);
    
    // Debug print for all users to check if chat IDs are being generated correctly
    print('User ID: $userId, Generated Chat ID: $chatId, Available unread counts: ${unreadCounts.keys.toList()}');
    
    // Debug the actual unread count value
    int count = unreadCounts[chatId] ?? 0;
    print('Unread count for $userId: $count (chatId: $chatId)');
    
    // Return the unread count or 0 if none
    return count;
  }

  Color getAvatarColor(String letter) {
    switch (letter.toLowerCase()) {
      case 'a':
        return const Color(0xFF7ECDC5);
      case 'c':
        return const Color(0xFF90DAD2);
      case 'g':
        return const Color(0xFF6BBFB5);
      case 'n':
        return const Color(0xFFA3E7DF);
      default:
        return const Color(0xFF6BBFB5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF0F7F5),
      appBar: AppBar(
        backgroundColor: Color(0xFFD0ECE8),
        elevation: 4.0,
        shadowColor: Colors.black.withOpacity(0.25),
        toolbarHeight: 100,
        leadingWidth: 56, // Default width of IconButton
        leading: IconButton(
          icon:
              const Icon(FontAwesomeIcons.arrowLeft, color: Color(0xC5000000)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Padding(
          padding: EdgeInsets.only(left: 0), // Adjust the spacing here
          child: Text(
            "Chats",
            style: GoogleFonts.poppins(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: Color(0xC5000000)),
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(
                right: 16.0), // Move the icon 16 pixels to the left
            child: IconButton(
              icon: const Icon(FontAwesomeIcons.solidBell,
                  color: Color(0xC5000000)),
              onPressed: () {
                Navigator.pushNamed(context, '/notifications');
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.all(7.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: Icon(FontAwesomeIcons.search,
                          color: Color(0x39000000)),
                      hintText: "Search by Name or Email..",
                      hintStyle: GoogleFonts.poppins(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w500,
                        color: Color(0x60000000),
                      ),
                      filled: true,
                      fillColor: Color(0xFFF1F1F1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        searchQuery = value.toLowerCase();
                      });
                    },
                  ),
                ),
                //SizedBox(width: 12),
                Container(
                  child: IconButton(
                    icon:
                        Icon(FontAwesomeIcons.users, color: Color(0xC5000000)),
                    onPressed: () {
                      Navigator.pushNamed(context, '/group-chats');
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(25),
                  topRight: Radius.circular(25),
                ),
              ),
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: users.length,
                      padding: const EdgeInsets.only(top: 8),
                      itemBuilder: (context, index) {
                        final user = users[index];
                        if (searchQuery.isNotEmpty &&
                            !user['username']
                                .toString()
                                .toLowerCase()
                                .contains(searchQuery) &&
                            !user['email']
                                .toString()
                                .toLowerCase()
                                .contains(searchQuery)) {
                          return Container();
                        }
                        // Get unread count for this user
                        final unreadCount = _getUnreadCount(user['id'].toString());
                        print('User ${user['username']} (${user['id']}): unreadCount = $unreadCount');
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: getAvatarColor(user['username'].toString()[0]),
                              backgroundImage: user['profilePicture'] != null && 
                                             user['profilePicture'].toString().isNotEmpty
                                  ? MemoryImage(base64Decode(user['profilePicture'].toString().split(',').last)) as ImageProvider
                                  : null,
                              child: (user['profilePicture'] == null || user['profilePicture'].toString().isEmpty)
                                  ? Text(
                                      user['username'].toString()[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w400,
                                        fontSize: 15,
                                      ),
                                    )
                                  : null,
                            ),
                            title: Text(
                              user['username'].toString(),
                              style: GoogleFonts.poppins(
                                fontSize: 18.0,
                                fontWeight: FontWeight.w500,
                                color: Color(0xC5000000),
                              ),
                            ),
                            subtitle: Text(
                              lastMessages[user['id'].toString()] ?? 'No messages yet',
                              style: GoogleFonts.poppins(
                                fontSize: 13.0,
                                fontWeight: FontWeight.w400,
                                color: Color(0x80000000),
                                fontStyle: lastMessages[user['id'].toString()] == null 
                                  ? FontStyle.italic 
                                  : FontStyle.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: unreadCount > 0
                              ? CircleAvatar(
                                  radius: 10,
                                  backgroundColor: Color(0xFF6BBFB5),
                                  child: Text(
                                    unreadCount.toString(),
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : null,
                            onTap: () async {
                              // Mark chat as read when user taps on it
                              if (currentUserId != null && unreadCount > 0) {
                                String chatId = _generateChatId(currentUserId!, user['id'].toString());
                                await _apiService.markChatAsRead(chatId, currentUserId!);
                                
                                // Update unread counts locally
                                if (mounted) {
                                  setState(() {
                                    unreadCounts[chatId] = 0;
                                  });
                                }
                              }
                              
                              Navigator.pushNamed(
                                context,
                                '/chat',
                                arguments: {
                                  'userId': user['id'].toString(),
                                  'username': user['username'].toString(),
                                  'profilePicture': user['profilePicture']?.toString(),
                                },
                              ).then((_) {
                                // Refresh unread counts when returning from chat
                                if (currentUserId != null) {
                                  _loadUnreadCounts();
                                }
                              });
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavBar(),
    );
  }
}

class BottomNavBar extends StatefulWidget {
  const BottomNavBar({super.key});

  @override
  _BottomNavBarState createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  int _currentIndex = 1;

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });

    switch (index) {
      case 0:
        // Action for File icon
        print("File icon tapped");
        break;
      case 1:
        // Action for Comment icon
        Navigator.pushNamed(context, '/chats');
        break;
      case 2:
        // Action for Home icon
        Navigator.pushNamed(context, '/chats');
        break;
      case 3:
        // Action for User icon
        Navigator.pushNamed(context, '/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: _currentIndex,
      selectedItemColor: Color(0xFF6BBFB5),
      unselectedItemColor: Color(0xA6000000),
      backgroundColor: Color(0xFFF0F7F5),
      type: BottomNavigationBarType.fixed,
      elevation: 5,
      showSelectedLabels: false,
      showUnselectedLabels: false,
      onTap: _onItemTapped,
      items: [
        BottomNavigationBarItem(
          icon: Icon(
            FontAwesomeIcons.solidFileLines,
            size: 24,
          ),
          label: "",
        ),
        BottomNavigationBarItem(
          icon: Icon(
            FontAwesomeIcons.solidCommentDots,
            size: 24,
          ),
          label: "",
        ),
        BottomNavigationBarItem(
          icon: Icon(
            FontAwesomeIcons.home,
            size: 24,
          ),
          label: "",
        ),
        BottomNavigationBarItem(
          icon: Icon(
            FontAwesomeIcons.userAlt,
            size: 24,
          ),
          label: "",
        ),
      ],
    );
  }
}
