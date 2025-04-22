import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pfe/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

class ManageGroupScreen extends StatefulWidget {
  final String groupName;
  final String groupId;
  final List<Map<String, dynamic>>? members; // Optional now, will load from API

  const ManageGroupScreen({
    super.key,
    required this.groupName,
    required this.groupId,
    this.members,
  });

  @override
  _ManageGroupScreenState createState() => _ManageGroupScreenState();
}

class _ManageGroupScreenState extends State<ManageGroupScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ApiService _apiService = ApiService();
  
  List<Map<String, dynamic>> groupMembers = [];
  List<Map<String, dynamic>> allUsers = [];
  String searchQuery = "";
  bool _isLoading = true;
  String? _currentUserId;
  String? _errorMessage;
  bool _isAdmin = false;
  String? _creatorId;

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }
  
  Future<void> _initializeScreen() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      
      // Get the current user ID first
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString('userId');
      print('Current user ID from SharedPreferences: $_currentUserId'); // Debug log
      
      if (_currentUserId == null) {
        throw Exception('Current user ID not found. Please log in again.');
      }
      
      if (widget.members != null) {
        // If members provided, use them initially
        groupMembers = List.from(widget.members!);
      }
      
      // Fetch group details from API
      await _fetchGroupDetails();
      
      // Fetch all users
      await _fetchAllUsers();
      
    } catch (e) {
      print('Error initializing screen: $e');
      setState(() {
        _errorMessage = 'Failed to load group data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _fetchGroupDetails() async {
    try {
      print('Fetching group details for group ID: ${widget.groupId}');
      final response = await _apiService.getChatGroupDetails(widget.groupId);
      print('Complete response from getChatGroupDetails: $response');
      
      // The API returns members as a separate array
      if (response.containsKey('members')) {
        final List<dynamic> members = response['members'];
        groupMembers = members.map((member) => {
          'id': member['id'].toString(),
          'name': member['username'].toString(),
          'image': 'assets/images/default_avatar.png', // Default image
        }).toList();
        print('Loaded ${groupMembers.length} members');
      }
      
      // Check if current user is the group creator (admin)
      // Creator ID is inside the 'group' object
      if (response.containsKey('group') && response['group'] is Map) {
        final groupData = response['group'] as Map<String, dynamic>;
        if (groupData.containsKey('creatorId')) {
          _creatorId = groupData['creatorId'].toString();
          print('Group creator ID from response: $_creatorId'); 
          print('Current user ID: $_currentUserId');
          
          // Make sure we're comparing strings
          final bool isAdmin = _currentUserId == _creatorId;
          print('Is admin based on ID comparison: $isAdmin');
          
          setState(() {
            _isAdmin = isAdmin;
          });
          
          print('Is admin (final result): $_isAdmin');
        } else {
          print('ERROR: creatorId not found in group data!');
          print('Group data: $groupData');
        }
      } else {
        print('ERROR: group object not found in API response!');
      }
    } catch (e) {
      print('Error fetching group details: $e');
      throw e;
    }
  }
  
  Future<void> _fetchAllUsers() async {
    try {
      // We'll use the search API instead of fetching all users at once
      allUsers = [];
    } catch (e) {
      print('Error fetching users: $e');
    }
  }

  // Add method to search for users to add to the group
  Future<void> _searchForUsers(String query) async {
    try {
      if (query.isEmpty) {
        setState(() {
          allUsers = [];
          _isLoading = false;
        });
        return;
      }
      
      // Only show loading indicator for the first search
      if (allUsers.isEmpty) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }
      
      // Use the new search API
      print('Searching for users with query: $query');
      final results = await _apiService.searchAvailableUsersForGroup(widget.groupId, query);
      print('Search returned ${results.length} results');
      
      setState(() {
        allUsers = results;
        _isLoading = false;
      });
    } catch (e) {
      print('Error searching for users: $e');
      setState(() {
        _errorMessage = 'Failed to search for users: $e';
        _isLoading = false;
      });
    }
  }
  
  // Get filtered members based on search query
  List<Map<String, dynamic>> getFilteredMembers() {
    return allUsers; 
  }
  
  Future<void> _addMember(Map<String, dynamic> user) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only group admin can add members')),
      );
      return;
    }
    
    try {
      setState(() {
        _errorMessage = null;
      });
      
      // Extract the ID as a String
      final String userId = user['id'].toString();
      
      // Optimistically add to UI
      setState(() {
        groupMembers.add({
          'id': userId,
          'name': user['name'],
          'image': user['image'] ?? 'assets/images/default_avatar.png',
        });
        _searchController.clear();
        searchQuery = "";
        allUsers = []; // Clear search results
      });
      
      // Call API to add member
      try {
        await _apiService.addGroupMember(widget.groupId, userId);
        print('Member added successfully!');
        
        // Add success feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user['name']} added to group'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (apiError) {
        print('API error details: $apiError');
        rethrow; // Re-throw to be caught by the outer catch block
      }
      
    } catch (e) {
      print('Error adding member: $e');
      
      // Remove from UI if API call failed
      setState(() {
        groupMembers.removeWhere((member) => member["id"] == user["id"]);
        _errorMessage = 'Failed to add member: $e';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add member: $e')),
      );
    }
  }
  
  Future<void> _removeMember(int index, Map<String, dynamic> member) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only group admin can remove members')),
      );
      return;
    }
    
    try {
      setState(() {
        _errorMessage = null;
      });
      
      // Optimistically remove from UI
      final removedMember = groupMembers[index];
      setState(() {
        groupMembers.removeAt(index);
      });
      
      // Call API to remove member
      await _apiService.removeGroupMember(widget.groupId, member['id']);
      
    } catch (e) {
      print('Error removing member: $e');
      
      // Add back to UI if API call failed
      setState(() {
        groupMembers.insert(index, member);
        _errorMessage = 'Failed to remove member: $e';
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove member: $e')),
      );
    }
  }
  
  Future<void> _deleteGroup() async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only group admin can delete the group')),
      );
      return;
    }
    
    try {
      setState(() {
        _isLoading = true;
      });
      
      await _apiService.deleteChatGroup(widget.groupId);
      
      Navigator.pop(context); // Close dialog
      Navigator.pop(context); // Close manage screen
      Navigator.pop(context); // Return to group list
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Group deleted successfully')),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete group: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredMembers = getFilteredMembers();
    
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Color(0xFFF0F7F5),
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(70),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: Colors.black.withOpacity(0.1),
                  width: 1,
                ),
              ),
            ),
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              toolbarHeight: 70,
              leading: IconButton(
                icon: Icon(FontAwesomeIcons.arrowLeft, color: Color(0xC5000000), size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                widget.groupName,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Color(0xC5000000),
                ),
              ),
            ),
          ),
        ),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF6BBFB5))),
      );
    }

    return Scaffold(
      backgroundColor: Color(0xFFF0F7F5),
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: Colors.black.withOpacity(0.1),
                width: 1,
              ),
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            toolbarHeight: 70,
            leading: IconButton(
              icon: Icon(FontAwesomeIcons.arrowLeft, color: Color(0xC5000000), size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              widget.groupName,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Color(0xC5000000),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_errorMessage != null)
            Container(
              color: Colors.red.shade100,
              padding: EdgeInsets.all(8),
              width: double.infinity,
              child: Text(
                _errorMessage!,
                style: TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
          
          SizedBox(height: 10),
          
          // Add New Members section - only visible to admin
          if (_isAdmin) ...[
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Icon(FontAwesomeIcons.circlePlus, size: 20, color: Color(0xC5000000)),
                  SizedBox(width: 8),
                  Text(
                    "Add New Members",
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xC5000000),
                    ),
                  ),
                ],
              ),
            ),
            // Search bar - only visible to admin
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: TextField(
                controller: _searchController,
                onChanged: (value) {
                  setState(() {
                    searchQuery = value;
                  });
                  // Call the search method when input changes
                  _searchForUsers(value);
                },
                decoration: InputDecoration(
                  hintText: "Search new members",
                  prefixIcon: Icon(FontAwesomeIcons.search, color: Color(0x39000000), size: 16),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 20),
                ),
              ),
            ),
            // Search Results - only visible to admin
            if (searchQuery.isNotEmpty && allUsers.isNotEmpty)
              Container(
                height: min(allUsers.length * 70.0, 200), // Limit height
                color: Colors.white,
                child: ListView.builder(
                  itemCount: allUsers.length,
                  itemBuilder: (context, index) {
                    final user = allUsers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Color(0xFF6BBFB5),
                        child: Text(
                          user["name"] != null && user["name"].toString().isNotEmpty 
                              ? user["name"].toString()[0].toUpperCase()
                              : '?',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                      title: Text(
                        user["name"],
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: Color(0xC5000000),
                        ),
                      ),
                      subtitle: Text(
                        user["email"],
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Color(0x99000000),
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(FontAwesomeIcons.plus, size: 16),
                        onPressed: () => _addMember(user),
                      ),
                    );
                  },
                ),
              ),
          ],
          
          SizedBox(height: 10),
          
          // Group Members Label
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Icon(FontAwesomeIcons.users, size: 20, color: Color(0xC5000000)),
                SizedBox(width: 8),
                Text(
                  _isAdmin ? "Edit Group Members" : "Group Members",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xC5000000),
                  ),
                ),
              ],
            ),
          ),
          
          // Current Members List
          Expanded(
            child: groupMembers.isEmpty 
              ? Center(child: Text("No members in this group", style: GoogleFonts.poppins(color: Colors.grey)))
              : ListView.builder(
                itemCount: groupMembers.length,
                itemBuilder: (context, index) {
                  final member = groupMembers[index];
                  // Don't show remove button for current user or if user is not admin
                  final isCurrentUser = member['id'] == _currentUserId;
                  final isCreator = member['id'] == _creatorId;
                  
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(0xFF6BBFB5),
                      child: Text(
                        member['name'] != null && member['name'].toString().isNotEmpty 
                            ? member['name'].toString()[0].toUpperCase()
                            : '?',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(
                      member["name"],
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Color(0xC5000000),
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        if (isCurrentUser)
                          Text(
                            "You",
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Color(0x99000000),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        if (isCreator)
                          Container(
                            margin: EdgeInsets.only(left: isCurrentUser ? 8 : 0),
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Color(0xFF6BBFB5).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "Admin",
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: Color(0xFF6BBFB5),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: (_isAdmin && !isCurrentUser && !isCreator) 
                      ? IconButton(
                          icon: Icon(FontAwesomeIcons.minus, size: 16),
                          onPressed: () => _removeMember(index, member),
                        )
                      : null,
                  );
                },
              ),
          ),
          
          // Delete Group Button - only visible to admin
          if (_isAdmin)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text("Delete Group?"),
                        content: Text("This action cannot be undone."),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text("Cancel"),
                          ),
                          TextButton(
                            onPressed: _deleteGroup,
                            child: Text(
                              "Delete",
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: Color(0xFFFFE5E5),
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(FontAwesomeIcons.trash, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        "Delete Group",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
} 