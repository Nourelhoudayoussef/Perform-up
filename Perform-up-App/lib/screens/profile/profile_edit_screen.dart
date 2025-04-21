import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pfe/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({Key? key}) : super(key: key);

  @override
  _ProfileEditScreenState createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final ApiService _apiService = ApiService();
  
  // Form controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  
  // User data
  String _userId = '';
  String? _profileImageUrl;
  File? _imageFile;
  bool _isLoading = true;
  bool _isSaving = false;
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
  }
  
  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _bioController.dispose();
    super.dispose();
  }
  
  // Load user data from API or shared preferences
  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Get user ID from shared preferences
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _userId = prefs.getString('userId') ?? '';
      });
      
      if (_userId.isEmpty) {
        throw Exception('User ID not found');
      }
      
      // Get user profile data from API
      final userProfile = await _apiService.getUserProfile(_userId);
      
      if (userProfile != null) {
        setState(() {
          _nameController.text = userProfile['name'] ?? '';
          _emailController.text = userProfile['email'] ?? '';
          _bioController.text = userProfile['bio'] ?? '';
          _profileImageUrl = userProfile['profileImage'];
        });
      } else {
        // Fallback to basic info if profile not found
        final userData = await _apiService.getCurrentUser();
        setState(() {
          _nameController.text = userData['username'] ?? '';
          _emailController.text = userData['email'] ?? '';
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading profile: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  // Pick image from gallery
  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        // Create a copy of the file in app directory for persistence
        final Directory appDir = await getApplicationDocumentsDirectory();
        final String fileName = path.basename(pickedFile.path);
        final File localImage = File('${appDir.path}/$fileName');
        
        // Copy the picked image to the app directory
        await File(pickedFile.path).copy(localImage.path);
        
        setState(() {
          _imageFile = localImage;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }
  
  // Save profile data and upload image
  Future<void> _saveProfile() async {
    setState(() {
      _isSaving = true;
    });
    
    try {
      // First update profile data
      await _apiService.updateUserProfile(_userId, {
        'name': _nameController.text,
        'bio': _bioController.text,
      });
      
      // Then upload image if selected
      if (_imageFile != null) {
        await _apiService.uploadProfileImage(_userId, _imageFile!.path);
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      
      // Go back to previous screen and indicate changes were made
      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate changes were made
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating profile: $e')),
      );
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFD0ECE8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.check, color: Colors.black87),
              onPressed: _isSaving ? null : _saveProfile,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6BBFB5)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Center(
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 64,
                          backgroundColor: const Color(0xFFD0ECE8),
                          backgroundImage: _imageFile != null
                              ? FileImage(_imageFile!)
                              : _profileImageUrl != null
                                  ? NetworkImage(_profileImageUrl!) as ImageProvider
                                  : null,
                          child: (_imageFile == null && _profileImageUrl == null)
                              ? Text(
                                  _nameController.text.isNotEmpty
                                      ? _nameController.text[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            height: 40,
                            width: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6BBFB5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 2,
                              ),
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.camera_alt,
                                size: 20,
                                color: Colors.white,
                              ),
                              onPressed: _pickImage,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Full name field
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Full name',
                      labelStyle: const TextStyle(
                        color: Colors.black54,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF6BBFB5),
                        ),
                      ),
                      prefixIcon: const Icon(
                        Icons.person_outline,
                        color: Color(0xFF6BBFB5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Email field (read-only)
                  TextField(
                    controller: _emailController,
                    readOnly: true, // User can't change email
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: const TextStyle(
                        color: Colors.black54,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.grey.shade200,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      prefixIcon: const Icon(
                        Icons.email_outlined,
                        color: Color(0xFF6BBFB5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Bio field
                  TextField(
                    controller: _bioController,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Bio',
                      alignLabelWithHint: true,
                      labelStyle: const TextStyle(
                        color: Colors.black54,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: Color(0xFF6BBFB5),
                        ),
                      ),
                      hintText: 'Write something about yourself...',
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _saveProfile,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6BBFB5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.0,
                            ),
                          )
                        : const Text(
                            'Save Profile',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                ],
              ),
            ),
    );
  }
} 