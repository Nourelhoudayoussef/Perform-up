import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pfe/screens/chat/manage_group_screen.dart';
import 'package:pfe/services/api_service.dart';
import 'package:pfe/services/websocket_service.dart';
import 'package:pfe/models/message.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

class GroupChatScreen extends StatefulWidget {
  final String groupName;
  final String? groupId;
  final List<Map<String, dynamic>>? messages;

  const GroupChatScreen({
    super.key,
    required this.groupName,
    this.groupId,
    this.messages,
  });

  @override
  _GroupChatScreenState createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final WebSocketService _webSocketService = WebSocketService();
  
  List<Map<String, dynamic>> messages = [];
  bool _isLoading = true;
  String? _currentUserId;
  String? _currentUsername;
  StreamSubscription? _chatSubscription;
  
  @override
  void initState() {
    super.initState();
    print('[GroupChatScreen] initState called');
    print('groupName: "${widget.groupName}"'); // Debug log
    print('groupId: "${widget.groupId}"'); // Debug log
    _initializeChat();
    
    // Add a post-frame callback to scroll to bottom after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToBottom();
      }
    });
  }
  
  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _chatSubscription?.cancel();
    super.dispose();
  }
  
  void _subscribeToWebSocketMessages() {
    if (widget.groupId == null) return;
    
    print('[GroupChatScreen] Subscribing to WebSocket messages for group: ${widget.groupId}');
    
    // Subscribe to group-specific WebSocket topic
    _webSocketService.subscribeToGroupChat(widget.groupId!);
    
    // Listen for new messages
    _chatSubscription = _webSocketService.chatMessageStream.listen((message) {
      print('[GroupChatScreen] Received WebSocket message: ${message.toJson()}');
      if (message.chatGroupId == widget.groupId) {
        final bool isSentByUser = message.senderId == _currentUserId;
        
        final newMessage = <String, dynamic>{
          "id": message.id,
          "text": message.content,
          "sender": <String, dynamic>{
            "name": isSentByUser ? "You" : message.senderName,
            "userId": message.senderId,
          },
          "isSentByUser": isSentByUser,
          "timestamp": message.timestamp,
        };
        
        // Add the message if it's not already in the list
        if (!messages.any((m) => m["id"] == message.id)) {
          setState(() {
            messages.add(newMessage);
            
            // Sort messages by timestamp
            messages.sort((a, b) {
              final aTime = a["timestamp"] as DateTime;
              final bTime = b["timestamp"] as DateTime;
              return aTime.compareTo(bTime);
            });
          });
          
          // Scroll to bottom when new messages arrive
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        }
      }
    });
  }
  
  Future<void> _initializeChat() async {
    print('[GroupChatScreen] _initializeChat called');
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Get user data
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString('userId');
      _currentUsername = prefs.getString('username');
      
      print('[GroupChatScreen] Current user: $_currentUserId, $_currentUsername');
      
      // Initialize empty messages list
      setState(() {
        messages = [];
      });
      
      // Try to load real messages if groupId is provided
      if (widget.groupId != null && _currentUserId != null) {
        await _loadMessages();
        
        // Connect to WebSocket if not already connected
        if (!_webSocketService.isConnected) {
          print('[GroupChatScreen] WebSocket not connected, connecting...');
          await _webSocketService.connect();
        }
        
        // Subscribe to WebSocket messages
        _subscribeToWebSocketMessages();
        
        // Mark chat as read
        try {
          await _apiService.markChatAsRead(widget.groupId!, _currentUserId!);
        } catch (e) {
          print('[GroupChatScreen] Error marking chat as read: $e');
        }
      }
      
      setState(() {
        _isLoading = false;
      });
      
      // Scroll to bottom after messages load
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToBottom();
        }
      });
    } catch (e) {
      print('[GroupChatScreen] Error initializing chat: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, // Since we're using reverse: true, 0.0 is the bottom
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }
  
  Future<void> _loadMessages() async {
    if (widget.groupId == null || _currentUserId == null) return;
    
    try {
      final apiMessages = await _apiService.getGroupMessages(widget.groupId!);
      
      // Convert API messages to UI format
      final List<Map<String, dynamic>> uiMessages = apiMessages.map((msg) {
        final bool isSentByUser = msg.senderId == _currentUserId;
        
        return <String, dynamic>{
          "id": msg.id,
          "text": msg.content,
          "sender": <String, dynamic>{
            "name": isSentByUser ? "You" : msg.senderName,
            "userId": msg.senderId, // Store user ID for fetching profile image later
          },
          "isSentByUser": isSentByUser,
          "timestamp": msg.timestamp,
        };
      }).toList();
      
      // Sort messages by timestamp
      uiMessages.sort((a, b) {
        final aTime = a["timestamp"] as DateTime;
        final bTime = b["timestamp"] as DateTime;
        return aTime.compareTo(bTime);
      });
      
      setState(() {
        messages = uiMessages;
      });
      
      // Fetch user profile images after loading messages
      _fetchUserProfiles();
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    // Clear the input field early for better UX
    _messageController.clear();
    
    // If we don't have groupId, use the mock implementation
    if (widget.groupId == null || _currentUserId == null) {
      setState(() {
        messages.add({
          "text": text,
          "sender": {"name": "You", "image": null, "userId": _currentUserId},
          "isSentByUser": true,
        });
      });
      return;
    }
    
    String? tempMessageId; // Declare tempMessageId at the method scope
    
    try {
      // Optimistically add message to UI
      tempMessageId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
      setState(() {
        messages.add({
          "id": tempMessageId,
          "text": text,
          "sender": {"name": "You", "image": null, "userId": _currentUserId},
          "isSentByUser": true,
          "isOptimistic": true, // Mark as optimistic to identify if needed
          "timestamp": DateTime.now(),
        });
      });
      
      // Scroll to the bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
      
      // Send message via the API
      final sentMessage = await _apiService.sendMessage(
        _currentUserId!,
        widget.groupId!,
        text
      );
      
      // Replace the optimistic message with the real one
      setState(() {
        final optimisticIndex = messages.indexWhere((msg) => msg["id"] == tempMessageId);
        if (optimisticIndex >= 0) {
          messages[optimisticIndex] = {
            "id": sentMessage.id,
            "text": sentMessage.content,
            "sender": {"name": "You", "userId": _currentUserId},
            "isSentByUser": true,
            "timestamp": sentMessage.timestamp,
          };
        }
      });
    } catch (e) {
      print('[GroupChatScreen] Error sending message: $e');
      // Remove the optimistic message
      if (tempMessageId != null) {
        setState(() {
          messages.removeWhere((msg) => msg["id"] == tempMessageId);
        });
      }
      
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Method to fetch user profile images
  Future<void> _fetchUserProfiles() async {
    if (messages.isEmpty) return;
    
    try {
      // Extract unique user IDs from messages (excluding the current user)
      final Set<String> userIds = messages
          .where((m) => !m['isSentByUser'] && m['sender'] != null && m['sender']['userId'] != null)
          .map((m) => m['sender']['userId'] as String)
          .toSet();
      
      if (userIds.isEmpty) return;
      
      // For each user, try to get their profile info including image
      for (final userId in userIds) {
        try {
          // This assumes you have or will create a method in ApiService to get user profiles
          final userProfile = await _apiService.getUserProfile(userId);
          
          if (userProfile != null && userProfile['profileImage'] != null) {
            // Update all messages from this user with their profile image
            setState(() {
              for (int i = 0; i < messages.length; i++) {
                if (!messages[i]['isSentByUser'] && 
                    messages[i]['sender'] != null && 
                    messages[i]['sender']['userId'] == userId) {
                  messages[i]['sender']['image'] = userProfile['profileImage'];
                }
              }
            });
          }
        } catch (e) {
          print('Error fetching profile for user $userId: $e');
        }
      }
    } catch (e) {
      print('Error in _fetchUserProfiles: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
            actions: [
              IconButton(
                icon: Icon(FontAwesomeIcons.ellipsisVertical, color: Color(0xC5000000), size: 20),
                onPressed: () {
                  if (widget.groupId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Cannot manage group: No group ID available')),
                    );
                    return;
                  }
                  
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ManageGroupScreen(
                        groupName: widget.groupName,
                        groupId: widget.groupId!,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
              ? Center(child: CircularProgressIndicator(color: Color(0xFF6BBFB5)))
              : NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification notification) {
                    if (notification is ScrollEndNotification) {
                      // Keep the view at the bottom when new messages arrive
                      if (_scrollController.position.pixels < _scrollController.position.maxScrollExtent - 100) {
                        _scrollToBottom();
                      }
                    }
                    return true;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true, // Start from bottom
                    padding: EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index]; // Access messages from end
                      
                      if (message.containsKey('isDate')) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              message['text'],
                              style: GoogleFonts.poppins(
                                color: Color(0x99000000),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }

                      final bool isSentByUser = message['isSentByUser'];
                      final sender = message['sender'];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: isSentByUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                          children: [
                            if (!isSentByUser) ...[
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Color(0xFF6BBFB5),
                                backgroundImage: sender['image'] != null && !sender['image'].toString().startsWith('assets/') 
                                  ? MemoryImage(base64Decode(sender['image'].toString().split(',').last)) as ImageProvider
                                  : null,
                                child: sender['image'] == null || sender['image'].toString().startsWith('assets/')
                                  ? Text(
                                      sender['name'][0].toUpperCase(),
                                      style: TextStyle(color: Colors.white),
                                    )
                                  : null,
                              ),
                              SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Column(
                                crossAxisAlignment: isSentByUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  if (!isSentByUser)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                                      child: Text(
                                        sender['name'],
                                        style: GoogleFonts.poppins(
                                          color: Color(0x99000000),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isSentByUser ? Color(0xFFD0ECE8) : Color(0xFFE4E4E4).withOpacity(0.83),
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(16),
                                        topRight: Radius.circular(16),
                                        bottomLeft: isSentByUser ? Radius.circular(16) : Radius.circular(0),
                                        bottomRight: isSentByUser ? Radius.circular(0) : Radius.circular(16),
                                      ),
                                    ),
                                    child: Text(
                                      message['text'],
                                      style: GoogleFonts.poppins(
                                        color: Color(0xC5000000),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: Color(0xFFF0F7F5),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 286,
                  height: 54,
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: "Send Message",
                      filled: true,
                      fillColor: Color(0xFFB1DDD4).withOpacity(0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 30, vertical: 16),
                    ),
                  ),
                ),
                SizedBox(width: 12),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Color(0xFF6BBFB5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
} 