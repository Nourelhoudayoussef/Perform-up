import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pfe/screens/chat/group_chat_screen.dart';
import 'package:pfe/services/api_service.dart';
import 'package:pfe/models/chat_group.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GroupChatsScreen extends StatefulWidget {
  const GroupChatsScreen({super.key});

  @override
  _GroupChatsScreenState createState() => _GroupChatsScreenState();
}

class _GroupChatsScreenState extends State<GroupChatsScreen> {
  bool isCreateNew = false;
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> selectedMembers = [];
  String _memberSearchQuery = "";
  int _currentIndex = 1;
  final ApiService _apiService = ApiService();
  
  // For API connectivity
  List<ChatGroup> _chatGroups = [];
  List<Map<String, dynamic>> _availableUsers = [];
  bool _isLoading = false;
  String? _currentUserId;
  Map<String, int> _unreadCounts = {}; // Store unread counts for each chat
  
  @override
  void initState() {
    super.initState();
    _loadCurrentUserAndData();
  }
  
  Future<void> _loadCurrentUserAndData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString('userId');
      
      if (_currentUserId != null) {
        setState(() {
          _isLoading = true;
        });
        
        try {
          // Make API calls in parallel for better performance
          final results = await Future.wait([
            _apiService.getUserChatGroups(_currentUserId!),
            _apiService.getUnreadCounts(_currentUserId!),
            _apiService.getApprovedUsers(),
          ]);
          
          final groups = results[0] as List<ChatGroup>;
          final unreadCounts = results[1] as Map<String, int>;
          final users = results[2] as List<Map<String, dynamic>>;
          
          setState(() {
            // Filter out individual chats and generic "Chat" entries
            _chatGroups = groups.where((group) => 
              !group.id.startsWith('individual_') && 
              !group.name.contains('Individual Chat') &&
              group.name.trim() != 'Chat'
            ).toList();
            
            _unreadCounts = unreadCounts;
            
            _availableUsers = users.where((user) => 
              user['id'].toString() != _currentUserId &&
              user['role']?.toString().toUpperCase() != 'ADMIN'
            ).toList();
            
            _isLoading = false;
          });
          
          print('Loaded groups: ${_chatGroups.map((g) => g.name).toList()}');
        } catch (e) {
          print('Error loading data: $e');
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('Error loading data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _searchChatGroups(String query) async {
    if (_currentUserId == null) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      if (query.isEmpty) {
        final groups = await _apiService.getUserChatGroups(_currentUserId!);
        setState(() {
          // Filter out individual chats and generic "Chat" entries
          _chatGroups = groups.where((group) => 
            !group.id.startsWith('individual_') && 
            !group.name.contains('Individual Chat') &&
            group.name.trim() != 'Chat'
          ).toList();
        });
      } else {
        final groups = await _apiService.searchChatGroups(query);
        setState(() {
          // Filter out individual chats and generic "Chat" entries
          _chatGroups = groups.where((group) => 
            !group.id.startsWith('individual_') && 
            !group.name.contains('Individual Chat') &&
            group.name.trim() != 'Chat'
          ).toList();
        });
      }
    } catch (e) {
      print('Error searching chat groups: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _createChatGroup() async {
    if (_groupNameController.text.isEmpty || selectedMembers.isEmpty || _currentUserId == null) {
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      List<String> memberIds = [];
      
      // If we have actual user data
      if (_availableUsers.isNotEmpty) {
        memberIds = selectedMembers.map((member) => member['id'].toString()).toList();
      } else {
        // Use mock data IDs
        memberIds = selectedMembers.map((member) => "mock_${member['name']}").toList();
      }
      
      // Add current user to members
      memberIds.add(_currentUserId!);
      
      // Create the chat group
      await _apiService.createChatGroup(
        _groupNameController.text.trim(),
        _currentUserId!,
        memberIds,
      );
      
      // Reset form and reload chat groups
      _groupNameController.clear();
      selectedMembers.clear();
      
      await _loadCurrentUserAndData();
      
      // Show success message and switch to search view
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chat group created successfully')),
        );
        setState(() {
          isCreateNew = false;
        });
      }
    } catch (e) {
      print('Error creating chat group: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating chat group')),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

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
    return Scaffold(
      backgroundColor: Color(0xFFF0F7F5),
      appBar: AppBar(
        backgroundColor: Color(0xFFD0ECE8),
        elevation: 4.0,
        shadowColor: Colors.black.withOpacity(0.25),
        toolbarHeight: 100,
        leading: IconButton(
          icon: Icon(FontAwesomeIcons.arrowLeft, color: Color(0xC5000000)),
          onPressed: () => Navigator.pushReplacementNamed(context, '/home'),
        ),
        title: Text(
          "Group Chats",
          style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w500,
            color: Color(0xC5000000),
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(FontAwesomeIcons.solidBell, color: Color(0xC5000000)),
            onPressed: () {
              Navigator.pushNamed(context, '/notifications');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(25),
              ),
              padding: EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => isCreateNew = false),
                      child: Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: !isCreateNew ? Color(0xFF6BBFB5) : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              FontAwesomeIcons.search,
                              size: 16,
                              color: !isCreateNew ? Colors.white : Color(0xFF6BBFB5),
                            ),
                            SizedBox(width: 8),
                            Text(
                              "Search",
                              style: GoogleFonts.poppins(
                                color: !isCreateNew ? Colors.white : Color(0xFF6BBFB5),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => isCreateNew = true),
                      child: Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: isCreateNew ? Color(0xFF6BBFB5) : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              FontAwesomeIcons.plus,
                              size: 16,
                              color: isCreateNew ? Colors.white : Color(0xFF6BBFB5),
                            ),
                            SizedBox(width: 8),
                            Text(
                              "Create new",
                              style: GoogleFonts.poppins(
                                color: isCreateNew ? Colors.white : Color(0xFF6BBFB5),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? Center(child: CircularProgressIndicator(color: Color(0xFF6BBFB5)))
              : (isCreateNew ? _buildCreateNewView() : _buildSearchView()),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Color(0xFF6BBFB5),
        unselectedItemColor: Color(0xA6000000),
        backgroundColor: Color(0xFFF0F7F5),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
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
      ),
    );
  }

  Widget _buildCreateNewView() {
    // Add debug prints to check conditions
    print('Group name: ${_groupNameController.text}');
    print('Selected members count: ${selectedMembers.length}');
    print('Is loading: $_isLoading');
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Group Name:",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xC5000000),
            ),
          ),
          SizedBox(height: 8),
          TextField(
            controller: _groupNameController,
            onChanged: (value) {
              // Force refresh UI when group name changes
              setState(() {});
            },
            decoration: InputDecoration(
              hintText: "Add group name",
              hintStyle: GoogleFonts.poppins(
                fontSize: 14.0,
                fontWeight: FontWeight.w500,
                color: Color(0x60000000),
              ),
              prefixIcon: Icon(FontAwesomeIcons.search, color: Color(0x39000000)),
              filled: true,
              fillColor: const Color(0xFFF1F1F1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
          SizedBox(height: 16),
          Text(
            "Members:",
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Color(0xC5000000),
            ),
          ),
          SizedBox(height: 8),
          TextField(
            decoration: InputDecoration(
              hintText: "Search group members..",
              hintStyle: GoogleFonts.poppins(
                fontSize: 14.0,
                fontWeight: FontWeight.w500,
                color: Color(0x60000000),),
              prefixIcon: Icon(FontAwesomeIcons.search, color: Color(0x39000000)),
              filled: true,
              fillColor: const Color(0xFFF1F1F1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 20),
            ),
            onChanged: (value) {
              setState(() {
                _memberSearchQuery = value;
              });
            },
          ),
          SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _availableUsers.length,
              itemBuilder: (context, index) {
                final member = _availableUsers[index];
                final isSelected = selectedMembers.any((selected) => 
                  selected['id'] == member['id']
                );
                
                // Filter based on search query
                if (_memberSearchQuery.isNotEmpty &&
                    !(member['name']?.toString().toLowerCase() ?? 
                      member['username']?.toString().toLowerCase() ?? '')
                        .contains(_memberSearchQuery.toLowerCase())) {
                  return Container();
                }
                
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Color(0xFF6BBFB5),
                    radius: 20,
                    child: Text(
                      (member['name'] ?? member['username'] ?? '?')[0].toUpperCase(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  title: Text(
                    member['name'] ?? member['username'] ?? '',
                    style: GoogleFonts.poppins(
                      color: Color(0xC5000000),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          // Only add the current member
                          if (!selectedMembers.any((m) => m['id'] == member['id'])) {
                            selectedMembers.add(member);
                          }
                        } else {
                          // Remove only the current member
                          selectedMembers.removeWhere((m) => m['id'] == member['id']);
                        }
                      });
                    },
                    activeColor: Color(0xFF6BBFB5),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                print('Button pressed');
                print('Group name is empty: ${_groupNameController.text.isEmpty}');
                print('Selected members: ${selectedMembers.length}');
                if (_groupNameController.text.isNotEmpty && selectedMembers.isNotEmpty && !_isLoading) {
                  _createChatGroup();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: (_groupNameController.text.isNotEmpty && selectedMembers.isNotEmpty && !_isLoading)
                    ? Color(0xFF6BBFB5)
                    : Color(0xFF6BBFB5).withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                elevation: 0,
              ),
              child: _isLoading 
                ? SizedBox(
                    width: 20, 
                    height: 20, 
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  )
                : Text(
                    "Create",
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchView() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: "Search by group name..",
              hintStyle: GoogleFonts.poppins(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w500,
                      color: Color(0x60000000),),
              prefixIcon: Icon(FontAwesomeIcons.search, color: Color(0x39000000)),
              filled: true,
              fillColor: const Color(0xFFF1F1F1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 20),
            ),
            onChanged: (value) {
              _searchChatGroups(value);
            },
          ),
          SizedBox(height: 16),
          Expanded(
            child: _chatGroups.isEmpty
              ? Center(
                  child: Text(
                    "No group chats found",
                    style: GoogleFonts.poppins(
                      color: Color(0x80000000),
                      fontSize: 16,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _chatGroups.length,
                  itemBuilder: (context, index) {
                    final group = _chatGroups[index];
                    return ListTile(
                      leading: 
                        const Icon(
                          FontAwesomeIcons.users,
                          color: Color(0xC5000000),
                          size: 20,
                        ),
                      
                      title: Text(
                        group.name,
                        style: GoogleFonts.poppins(
                          color: Color(0xC5000000),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: group.lastMessage != null
                        ? Text(
                            group.lastMessage!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: Color(0x80000000),
                              fontSize: 12,
                            ),
                          )
                        : null,
                      trailing: _unreadCounts[group.id] != null && _unreadCounts[group.id]! > 0
                        ? CircleAvatar(
                            radius: 10,
                            backgroundColor: Color(0xFF6BBFB5),
                            child: Text(
                              _unreadCounts[group.id]!.toString(),
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : null,
                      onTap: () async {
                        // Mark chat as read when user taps on it
                        if (_currentUserId != null && (_unreadCounts[group.id] ?? 0) > 0) {
                          try {
                            await _apiService.markChatAsRead(group.id, _currentUserId!);
                            
                            // Update unread counts locally
                            setState(() {
                              _unreadCounts[group.id] = 0;
                            });
                          } catch (e) {
                            print('Error marking chat as read: $e');
                          }
                        }
                        
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GroupChatScreen(
                              groupName: group.name,
                              groupId: group.id,
                              messages: null, // Will use default messages
                            ),
                          ),
                        ).then((_) {
                          // Refresh data when returning from chat screen
                          _loadCurrentUserAndData();
                        });
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
} 