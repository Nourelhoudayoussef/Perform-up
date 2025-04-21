import 'package:flutter/material.dart';
import 'package:pfe/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pfe/screens/profile/profile_edit_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // First get current user data directly from API
      final userData = await _apiService.getCurrentUser();
      setState(() {
        _userData = userData;
      });
      
      if (_userData != null && _userData!['id'] != null) {
        // Then get the full profile with profile image
        final userId = _userData!['id'].toString();
        
        print('Loading profile data for user ID: $userId'); // Debug log
        
        // Force-refresh the profile from the server
        final profileData = await _apiService.getUserProfile(userId);
        
        print('Profile data loaded: $profileData'); // Debug log
        
        setState(() {
          _profileData = profileData;
        });
      }
    } catch (e) {
      print('Error loading user data: $e'); // Debug log
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading profile: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error logging out: $e')),
        );
      }
    }
  }

  Future<void> _navigateToEditProfile() async {
    // Create a new profile edit screen instance to ensure it's fresh
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileEditScreen()),
    );
    
    // If the edit screen returns true, refresh the profile data
    if (result == true) {
      print('Profile was edited, refreshing data...'); // Debug log
      await _loadUserData();
      
      // Force UI refresh
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: const Color(0xFF6BBFB5),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _navigateToEditProfile,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _userData == null
              ? const Center(child: Text('No user data available'))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 60,
                              backgroundColor: const Color(0xFF6BBFB5),
                              backgroundImage: _profileData != null && 
                                             _profileData!['profileImage'] != null
                                  ? NetworkImage(_profileData!['profileImage'] as String)
                                  : null,
                              child: (_profileData == null || _profileData!['profileImage'] == null)
                                  ? Text(
                                      _userData!['username']?[0].toUpperCase() ?? 'U',
                                      style: const TextStyle(
                                        fontSize: 40,
                                        color: Colors.white,
                                      ),
                                    )
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: InkWell(
                                onTap: _navigateToEditProfile,
                                child: Container(
                                  height: 35,
                                  width: 35,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF6BBFB5),
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Color(0xFF6BBFB5),
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildProfileItem('Username', _userData!['username'] ?? 'N/A'),
                      _buildProfileItem('Email', _userData!['email'] ?? 'N/A'),
                      _buildProfileItem('Role', _userData!['role'] ?? 'N/A'),
                      if (_profileData != null && _profileData!['bio'] != null)
                        _buildProfileItem('Bio', _profileData!['bio'] as String),
                      const Spacer(),
                      Center(
                        child: ElevatedButton(
                          onPressed: _logout,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6BBFB5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 50,
                              vertical: 15,
                            ),
                          ),
                          child: const Text(
                            'Logout',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }

  Widget _buildProfileItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }
} 