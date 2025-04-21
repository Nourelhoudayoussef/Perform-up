import 'package:flutter/material.dart';
import 'package:pfe/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UsersListScreen extends StatefulWidget {
  const UsersListScreen({super.key});

  @override
  State<UsersListScreen> createState() => _UsersListScreenState();
}

class _UsersListScreenState extends State<UsersListScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUserId = prefs.getString('userId');
      if (currentUserId == null) {
        throw Exception('User ID not found');
      }
      setState(() {
        _currentUserId = currentUserId;
      });

      final users = await _apiService.getApprovedUsers();
      // Filter out current user from the list
      final filteredUsers = users.where((user) => user['id'] != currentUserId).toList();
      
      setState(() {
        _users = filteredUsers;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading users: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading users: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startConversation(String userId, String username) async {
    try {
      if (_currentUserId == null) return;

      // Create a new chat group with the selected user
      final group = await _apiService.createChatGroup(
        username, // Use the other user's name as group name
        _currentUserId!,
        [_currentUserId!, userId], // Add both users to the group
      );

      if (mounted) {
        // Navigate to chat screen with the new group
        Navigator.pushNamed(
          context,
          '/chat',
          arguments: {
            'groupId': group.id,
            'groupName': group.name,
          },
        );
      }
    } catch (e) {
      print('Error starting conversation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting conversation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? const Center(child: Text('No users available'))
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(user['username'][0].toUpperCase()),
                      ),
                      title: Text(user['username']),
                      subtitle: Text(user['email']),
                      trailing: IconButton(
                        icon: const Icon(Icons.chat),
                        onPressed: () => _startConversation(user['id'], user['username']),
                      ),
                    );
                  },
                ),
    );
  }
} 