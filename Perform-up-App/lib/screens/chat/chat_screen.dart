import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pfe/services/api_service.dart';
import 'package:pfe/services/websocket_service.dart';
import 'package:pfe/models/message.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pfe/models/chat_group.dart';
import 'dart:async';
import 'dart:convert';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String username;
  final String? profilePicture;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.username,
    this.profilePicture,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final WebSocketService _webSocketService = WebSocketService();
  List<Message> _messages = [];
  bool _isLoading = true;
  String? _currentUserId;
  String? _currentUsername;
  StreamSubscription? _chatSubscription;

  @override
  void initState() {
    super.initState();
    print('ChatScreen initialized with:'); // Debug log
    print('userId: "${widget.userId}"'); // Debug log
    print('username: "${widget.username}"'); // Debug log
    print('profilePicture: "${widget.profilePicture}"'); // Debug log
    _loadUserData();
    _initializeChat();
    
    // Subscribe to websocket messages
    _subscribeToWebSocketMessages();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _chatSubscription?.cancel();
    super.dispose();
  }

  // Subscribe to WebSocket messages
  void _subscribeToWebSocketMessages() {
    _chatSubscription = _webSocketService.chatMessageStream.listen((message) {
      // Check if this message belongs to this chat conversation
      if (message.chatGroupId == generateChatGroupId(_currentUserId!, widget.userId)) {
        setState(() {
          // Add the message if it's not already in the list
          if (!_messages.any((m) => m.id == message.id)) {
            _messages.add(message);
            _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          }
        });
        
        // Scroll to bottom after new message is received
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    });
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');
      final username = prefs.getString('username');
      
      print('Loaded user data:'); // Debug log
      print('userId: "$userId"'); // Debug log
      print('username: "$username"'); // Debug log
      
      if (mounted) {
        setState(() {
          _currentUserId = userId;
          _currentUsername = username;
        });
      }
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> _initializeChat() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      await _loadUserData();
      await _loadMessages();
      
      if (_webSocketService.isConnected) {
        print('WebSocket already connected');
      } else {
        print('Connecting to WebSocket...');
        await _webSocketService.connect();
      }
    } catch (e) {
      print('Error initializing chat: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMessages() async {
    if (_currentUserId == null) {
      print('Current user ID is null, cannot load messages');
      return;
    }
    
    try {
      final groupId = generateChatGroupId(_currentUserId!, widget.userId);
      print('Loading messages for chat group: $groupId');
      
      final messages = await _apiService.getIndividualMessages(
        _currentUserId!,
        widget.userId,
      );
      
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String generateChatGroupId(String userId1, String userId2) {
    List<String> ids = [userId1, userId2];
    ids.sort(); // Sort to ensure the same ID regardless of order
    return ids.join('_');
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
      // Send message via REST API
      final message = await _apiService.sendIndividualMessage(
        _currentUserId!,
        widget.userId,
        content,
      );

      // Also send via WebSocket for real-time delivery
      await _webSocketService.sendChatMessage(widget.userId, content);

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
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leadingWidth: 56,
        leading: IconButton(
          icon: const Icon(FontAwesomeIcons.arrowLeft, color: Color(0xC5000000)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey[300],
              backgroundImage: widget.profilePicture != null && widget.profilePicture!.isNotEmpty
                  ? MemoryImage(base64Decode(widget.profilePicture!.split(',').last)) as ImageProvider
                  : null,
              child: widget.profilePicture == null || widget.profilePicture!.isEmpty
                  ? Text(
                      widget.username[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              widget.username,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: const Color(0xC5000000),
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
