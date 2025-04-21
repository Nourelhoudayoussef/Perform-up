import 'package:flutter/material.dart';
import 'package:pfe/services/api_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  _ManageUsersScreenState createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _pendingUsers = [];
  List<dynamic> _approvedUsers = [];
  bool _isLoading = true;
  bool _isSearching = false;
  String _searchQuery = "";
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final pendingUsers = await _apiService.getPendingUsers();
      final approvedUsers = await _apiService.getApprovedUsers();
      
      setState(() {
        _pendingUsers = pendingUsers;
        _approvedUsers = approvedUsers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<dynamic> get filteredPendingUsers {
    if (_searchQuery.isEmpty) return _pendingUsers;
    return _pendingUsers.where((user) {
      return user["username"].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
             user["email"].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
             user["role"].toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  List<dynamic> get filteredApprovedUsers {
    if (_searchQuery.isEmpty) return _approvedUsers;
    return _approvedUsers.where((user) {
      return user["username"].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
             user["email"].toString().toLowerCase().contains(_searchQuery.toLowerCase()) ||
             user["role"].toString().toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _approveUser(String userId) async {
    try {
      await _apiService.approveUser(userId);
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User approved successfully'),
            backgroundColor: Color(0xFF6BBFB5),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error approving user: $e')),
        );
      }
    }
  }

  Future<void> _deleteUser(String userId) async {
    try {
      await _apiService.deleteUser(userId);
      await _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User deleted successfully'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting user: $e')),
        );
      }
    }
  }

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // Clear all stored data
      
      // Navigate to login screen and remove all previous routes
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error logging out: $e')),
      );
    }
  }

  void _showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Logout'),
          content: Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              child: Text('Cancel', style: TextStyle(color: Colors.black)),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: Text('Logout', style: TextStyle(color: Color(0xFF6BBFB5))),
              onPressed: () {
                Navigator.pop(context);
                _logout();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: _isSearching 
            ? Expanded(child: _buildSearchField())
            : Text(
                "Manage Users",
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: Color(0xC5000000),
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search, color: Color(0xC5000000)),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  _searchQuery = "";
                }
              });
            },
          ),
          IconButton(
            icon: Icon(FontAwesomeIcons.rightFromBracket, color: Color(0xC5000000), size: 20),
            onPressed: _showLogoutConfirmation,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Color(0xFF6BBFB5)))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUsers,
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSectionTitle("Authentication Requests"),
                        SizedBox(height: 16),
                        filteredPendingUsers.isEmpty && _searchQuery.isNotEmpty
                            ? _buildNoResults("requests")
                            : _buildAuthRequestsList(),
                        SizedBox(height: 24),
                        _buildSectionTitle("Users"),
                        SizedBox(height: 16),
                        filteredApprovedUsers.isEmpty && _searchQuery.isNotEmpty
                            ? _buildNoResults("users")
                            : _buildUsersList(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: 'Search by name, email, or role...',
        border: InputBorder.none,
        hintStyle: GoogleFonts.poppins(
          color: Color(0x99000000),
          fontSize: 16,
        ),
      ),
      style: GoogleFonts.poppins(
        color: Color(0xC5000000),
        fontSize: 16,
      ),
      onChanged: (query) {
        setState(() {
          _searchQuery = query;
        });
      },
    );
  }

  Widget _buildNoResults(String type) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          'No $type found matching "${_searchController.text}"',
          style: GoogleFonts.poppins(
            fontSize: 14,
            color: Color(0x99000000),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Icon(
          title == "Authentication Requests" 
              ? Icons.people_outline 
              : Icons.group_outlined,
          color: Color(0xC5000000),
        ),
        SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: Color(0xC5000000),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthRequestsList() {
    return Column(
      children: filteredPendingUsers.map((user) {
        return Container(
          margin: EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
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
                backgroundColor: Color(0xFF6BBFB5),
                child: Text(
                  user["username"][0].toUpperCase(),
                  style: TextStyle(color: Colors.white),
                ),
                radius: 25,
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user["username"] ?? 'Unknown',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xC5000000),
                      ),
                    ),
                    Text(
                      "Role: ${user["role"] ?? 'Unknown'}",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Color(0x99000000),
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => _approveUser(user["id"]),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF6BBFB5),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text('Accept'),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUsersList() {
    return Column(
      children: filteredApprovedUsers.map((user) {
        return Container(
          margin: EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
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
                backgroundColor: Color(0xFF6BBFB5),
                child: Text(
                  user["username"][0].toUpperCase(),
                  style: TextStyle(color: Colors.white),
                ),
                radius: 25,
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user["username"] ?? 'Unknown',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xC5000000),
                      ),
                    ),
                    Text(
                      "Role: ${user["role"] ?? 'Unknown'}",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Color(0x99000000),
                      ),
                    ),
                    Text(
                      "Email: ${user["email"] ?? 'No email'}",
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: Color(0x99000000),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_vert, color: Color(0xFF6BBFB5)),
                onPressed: () {
                  _showUserOptions(context, user);
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  void _showUserOptions(BuildContext context, Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red),
                title: Text('Remove User'),
                onTap: () {
                  Navigator.pop(context);
                  _showRemoveConfirmation(context, user);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showRemoveConfirmation(BuildContext context, Map<String, dynamic> user) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Remove User'),
          content: Text('Are you sure you want to remove ${user["username"]}?'),
          actions: [
            TextButton(
              child: Text('Cancel', style: TextStyle(color: Colors.black)),
              onPressed: () => Navigator.pop(context),
            ),
            TextButton(
              child: Text('Remove', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.pop(context);
                _deleteUser(user["id"]);
              },
            ),
          ],
        );
      },
    );
  }
} 