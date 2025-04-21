import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pfe/services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _apiService = ApiService();
  String? username;
  int _currentIndex = 1; // Start with chat tab selected
  List<Map<String, dynamic>> users = [];
  bool isLoading = true;
  String searchQuery = "";
  String? error;

  @override
  void initState() {
    super.initState();
    _verifyTokenAndLoadData();
  }

  Future<void> _verifyTokenAndLoadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final userId = prefs.getString('userId');
      
      // Debug print all stored values
      print('DEBUG - Stored values in home screen:');
      print('Token: ${token != null ? 'exists' : 'missing'}');
      print('UserId: $userId');
      print('Username: ${prefs.getString('username')}');
      print('Role: ${prefs.getString('role')}');
      
      if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
        print('Missing token or userId, redirecting to login');
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }
      
      // Skip token validation for now and just load the data
      // This helps when the backend is having connection issues
      _loadUsername();
      _loadUsers();
    } catch (e) {
      print('Error in verification flow: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Authentication error. Please log in again.')),
        );
        Navigator.pushReplacementNamed(context, '/login');
      }
    }
  }

  Future<void> _loadUsername() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      username = prefs.getString('username') ?? 'User';
    });
  }

  Future<void> _loadUsers() async {
    try {
      setState(() {
        isLoading = true;
        error = null;
      });
      
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('userId');
      
      print('DEBUG - SharedPreferences contents:');
      print('userId: $currentUserId');
      print('username: ${prefs.getString('username')}');
      print('role: ${prefs.getString('role')}');
      print('token exists: ${prefs.getString('token') != null}');
      
      if (currentUserId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Session expired. Please log in again.')),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      try {
        final fetchedUsers = await _apiService.getApprovedUsers();
        final filteredUsers = fetchedUsers.where((user) => user['id'] != currentUserId).toList();
        
        if (mounted) {
          setState(() {
            users = filteredUsers;
            isLoading = false;
          });
        }
      } catch (e) {
        print('Error fetching users: $e');
        if (e.toString().contains('403') || 
            e.toString().contains('401') || 
            e.toString().contains('authentication') ||
            e.toString().contains('token')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Session expired. Please log in again.')),
            );
            Navigator.pushReplacementNamed(context, '/login');
          }
        } else {
          if (mounted) {
            setState(() {
              error = e.toString();
              isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          isLoading = false;
        });
      }
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
        title: Text(
          "Chats",
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: Color(0xC5000000),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final role = prefs.getString('role');
              print('DEBUG - Stored role: $role');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Current role: $role')),
              );
            },
            child: Text('Check Role'),
          ),
          Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: IconButton(
              icon: const Icon(FontAwesomeIcons.solidBell, color: Color(0xC5000000)),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final role = prefs.getString('role');
                print('DEBUG - Navigating to notifications with role: $role');
                if (role != null) {
                  Navigator.pushNamed(
                    context, 
                    '/notifications',
                    arguments: {'role': role},
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: User role not found')),
                  );
                }
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(7.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: Icon(FontAwesomeIcons.search, color: Color(0x39000000)),
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
              ],
            ),
          ),
          Expanded(
            child: isLoading
                ? Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Error loading users:',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.red,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              error!,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: Colors.red[700],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadUsers,
                              child: Text('Retry'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFF6BBFB5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : users.isEmpty
                        ? Center(
                            child: Text(
                              'No users available',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final user = users[index];
                              if (searchQuery.isNotEmpty &&
                                  !user['username'].toString().toLowerCase().contains(searchQuery) &&
                                  !user['email'].toString().toLowerCase().contains(searchQuery)) {
                                return Container();
                              }
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Color(0xFF6BBFB5),
                                  child: Text(
                                    user['username'].toString()[0].toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
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
                                  user['email'].toString(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 15.0,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0x33000000),
                                  ),
                                ),
                                onTap: () {
                                  Navigator.pushNamed(
                                    context,
                                    '/chat',
                                    arguments: {
                                      'userId': user['id'].toString(),
                                      'username': user['username'].toString(),
                                    },
                                  );
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Color(0xFF6BBFB5),
        unselectedItemColor: Color(0xA6000000),
        backgroundColor: Color(0xFFF0F7F5),
        type: BottomNavigationBarType.fixed,
        elevation: 5,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        onTap: (index) async {
          setState(() {
            _currentIndex = index;
          });
          switch (index) {
            case 0:
              break;
            case 1:
              break;
            case 2:
              final prefs = await SharedPreferences.getInstance();
              final role = prefs.getString('role');
              print('Current role from SharedPreferences: $role'); 
              if (role != null) {
                Navigator.pushNamed(
                  context, 
                  '/notifications',
                  arguments: {'role': role},
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: User role not found')),
                );
              }
              break;
            case 3:
              Navigator.pushNamed(context, '/profile');
              break;
          }
        },
        items: [
          BottomNavigationBarItem(
            icon: Icon(FontAwesomeIcons.home, size: 24),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Icon(FontAwesomeIcons.solidCommentDots, size: 24),
            label: "Chat",
          ),
          BottomNavigationBarItem(
            icon: Icon(FontAwesomeIcons.solidBell, size: 24),
            label: "Notifications",
          ),
          BottomNavigationBarItem(
            icon: Icon(FontAwesomeIcons.userAlt, size: 24),
            label: "Profile",
          ),
        ],
      ),
    );
  }
} 