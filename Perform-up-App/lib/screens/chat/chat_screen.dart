import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pfe/services/api_service.dart';
import 'package:pfe/models/message.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pfe/models/chat_group.dart';
import 'dart:async';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String username;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.username,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  List<Message> _messages = [];
  bool _isLoading = true;
  Timer? _messageTimer;
  String? _currentUserId;
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    print('ChatScreen initialized with:'); // Debug log
    print('userId: "${widget.userId}"'); // Debug log
    print('username: "${widget.username}"'); // Debug log
    _loadUserData();
    _initializeChat();
    // Start periodic message checking every 3 seconds
    _messageTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _loadMessages();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');
      final username = prefs.getString('username');
      
      print('Loaded user data:'); // Debug log
      print('userId: "$userId"'); // Debug log
      print('username: "$username"'); // Debug log
      
      if (userId == null) {
        throw Exception('User ID not found');
      }
      
      setState(() {
        _currentUserId = userId;
        _currentUsername = username;
      });
      
      await _loadMessages();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading user data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMessages() async {
    try {
      if (_currentUserId == null) return;
      
      print('Loading messages between $_currentUserId and ${widget.userId}'); // Debug log
      
      final newMessages = await _apiService.getIndividualMessages(
        _currentUserId!,
        widget.userId,
      );
      
      print('Loaded ${newMessages.length} messages'); // Debug log
      
      // Mark chat as read when loading messages
      String chatId = generateChatGroupId(_currentUserId!, widget.userId);
      await _apiService.markChatAsRead(chatId, _currentUserId!);
      
      if (mounted) {
        setState(() {
          // Check if there are new messages
          if (_messages.isEmpty) {
            _messages = newMessages;
          } else if (newMessages.isNotEmpty) {
            // Check if last message is different
            final lastExistingMessage = _messages.last;
            final lastNewMessage = newMessages.last;
            
            if (lastExistingMessage.id != lastNewMessage.id) {
              _messages = newMessages;
              // Only scroll to bottom if we received new messages
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToBottom();
              });
            }
          }
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;
    
    final String content = _messageController.text.trim();
    
    // Create a temporary message for the UI
    final tempMessage = Message(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _currentUserId!,
      chatGroupId: generateChatGroupId(_currentUserId!, widget.userId),
      content: content,
      timestamp: DateTime.now(),
      senderName: _currentUsername ?? 'Me',
    );
    
    setState(() {
      _messages.add(tempMessage);
      _messageController.clear();
    });
    
    // Scroll to bottom after message is added
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    try {
      final message = await _apiService.sendIndividualMessage(
        _currentUserId!,
        widget.userId,
        content,
      );

      // Replace the temporary message with the real one
      setState(() {
        final index = _messages.indexWhere((m) => 
          m.id.startsWith('temp_') && 
          m.content == content && 
          m.senderId == _currentUserId);
          
        if (index != -1) {
          _messages[index] = message;
        }
      });
    } catch (e) {
      print('Error sending message: $e');
      
      // Remove the temporary message
      setState(() {
        _messages.removeWhere((m) => 
          m.id.startsWith('temp_') && 
          m.content == content && 
          m.senderId == _currentUserId);
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  // Helper method to generate a consistent chatGroupId
  String generateChatGroupId(String userId1, String userId2) {
    final List<String> ids = [userId1, userId2]..sort();
    return 'individual_${ids[0]}_${ids[1]}';
  }

  Future<void> _initializeChat() async {
    try {
      await _loadMessages();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing chat: $e')),
        );
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFD0ECE8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: const Color(0xFF90DAD2),
              child: Text(
                widget.username[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              widget.username,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMe = message.senderId == _currentUserId;

                          return Align(
                            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: isMe ? const Color(0xFFD0ECE8) : const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 0),
                                  bottomRight: Radius.circular(isMe ? 0 : 16),
                                ),
                              ),
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.75,
                              ),
                              child: Text(
                                message.content,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(
                  color: Colors.grey.withOpacity(0.2),
                ),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD0ECE8).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Send Message',
                          hintStyle: TextStyle(color: Colors.black54),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: const Color(0xFF6BBFB5),
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      onTap: _sendMessage,
                      borderRadius: BorderRadius.circular(24),
                      child: const Padding(
                        padding: EdgeInsets.all(10),
                        child: Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
