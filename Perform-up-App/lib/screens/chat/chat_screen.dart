import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:pfe/services/api_service.dart';
import 'package:pfe/services/websocket_service.dart';
import 'package:pfe/models/message.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pfe/models/chat_group.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
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
  bool _isDisposed = false;
  Timer? _refreshTimer;

  // Speech to text variables
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _initializeChat();
    _subscribeToWebSocketMessages();
    _startRefreshTimer();
    _initSpeech();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToBottom();
      }
    });
  }

  void _startRefreshTimer() {
    // Refresh messages every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isDisposed && mounted) {
        _loadMessages();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _messageController.dispose();
    _scrollController.dispose();
    _chatSubscription?.cancel();
    _refreshTimer?.cancel();
    _stopListening();
    _speech.cancel();
    super.dispose();
  }

  void _subscribeToWebSocketMessages() {
    _chatSubscription?.cancel();
    
    _chatSubscription = _webSocketService.chatMessageStream.listen((message) {
      if (_isDisposed) return;
      
      if (message.chatGroupId == generateChatGroupId(_currentUserId!, widget.userId)) {
        if (mounted) {
          setState(() {
            if (!_messages.any((m) => m.id == message.id)) {
              _messages.add(message);
              _messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            }
          });
          
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _scrollToBottom();
            }
          });
        }
      }
    });
  }

  Future<void> _loadUserData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');
      final username = prefs.getString('username');
      
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
      
      if (!_webSocketService.isConnected) {
        await _webSocketService.connect();
      }
      
      final chatGroupId = generateChatGroupId(_currentUserId!, widget.userId);
      _webSocketService.subscribeToChatGroup(chatGroupId);
    } catch (e) {
      print('Error initializing chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error connecting to chat: $e'),
            backgroundColor: Colors.red,
          ),
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

  Future<void> _loadMessages() async {
    if (_currentUserId == null) return;
    
    try {
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
          if (mounted) {
            _scrollToBottom();
          }
        });
      }
    } catch (e) {
      print('Error loading messages: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading messages: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String generateChatGroupId(String userId1, String userId2) {
    List<String> ids = [userId1, userId2];
    ids.sort();
    return 'individual_${ids[0]}_${ids[1]}';
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_isDisposed) return;
    if (_messageController.text.trim().isEmpty) return;
    
    final String content = _messageController.text.trim();
    
    final tempMessage = Message(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      senderId: _currentUserId!,
      receiverId: widget.userId,
      chatGroupId: generateChatGroupId(_currentUserId!, widget.userId),
      content: content,
      timestamp: DateTime.now(),
      senderName: _currentUsername ?? 'Me',
    );
    
    if (mounted) {
      setState(() {
        _messages.add(tempMessage);
        _messageController.clear();
      });
    }
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToBottom();
      }
    });

    try {
      final message = await _apiService.sendIndividualMessage(
        _currentUserId!,
        widget.userId,
        content,
      );

      await _webSocketService.sendChatMessage(widget.userId, content);

      if (mounted) {
        setState(() {
          final index = _messages.indexWhere((m) => 
            m.id.startsWith('temp_') && 
            m.content == content && 
            m.senderId == _currentUserId);
            
          if (index != -1) {
            _messages[index] = message;
          }
        });
      }
    } catch (e) {
      print('Error sending message: $e');
      
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => 
            m.id.startsWith('temp_') && 
            m.content == content && 
            m.senderId == _currentUserId);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Initialize speech to text
  void _initSpeech() async {
    // Request permission first
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      await _speech.initialize(
        onStatus: (status) => print('Speech status: $status'),
        onError: (error) => print('Speech error: $error'),
      );
    } else {
      print('Microphone permission not granted');
    }
  }

  // Start listening
  Future<void> _startListening() async {
    // Check current permission status
    final status = await Permission.microphone.status;
    
    if (status.isDenied) {
      // If permission is denied, request it again
      final result = await Permission.microphone.request();
      if (!result.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Microphone permission is required for voice input'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }

    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) => print('Speech status: $status'),
        onError: (error) => print('Speech error: $error'),
      );
      
      if (available) {
        setState(() => _isListening = true);
        await _speech.listen(
          onResult: (result) {
            setState(() {
              _lastWords = result.recognizedWords;
              if (result.finalResult) {
                _messageController.text = _lastWords;
                _isListening = false;
              }
            });
          },
          localeId: 'en_US',
          cancelOnError: true,
          partialResults: true,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Speech recognition not available'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  // Stop listening
  void _stopListening() {
    if (_isListening) {
      _speech.stop();
      setState(() {
        _isListening = false;
        if (_lastWords.isNotEmpty) {
          _messageController.text = _lastWords;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD0ECE8),
        elevation: 0,
        leadingWidth: 56,
        leading: IconButton(
          icon: const Icon(FontAwesomeIcons.arrowLeft, color: Color(0xC5000000)),
          onPressed: () {
            Navigator.of(context).pop(true);
          },
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
                    ? Center(
                        child: Text(
                          'No messages yet',
                          style: GoogleFonts.poppins(
                            color: const Color(0x80000000),
                            fontSize: 14,
                          ),
                        ),
                      )
                    : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _messages.length,
                        reverse: true,
                          itemBuilder: (context, index) {
                            final message = _messages[_messages.length - 1 - index];
                            final isMe = message.senderId == _currentUserId;

                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                color: isMe ? const Color(0xFFD0ECE8) : Colors.white,
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isMe ? 16 : 0),
                                    bottomRight: Radius.circular(isMe ? 0 : 16),
                                  ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                                ),
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                                ),
                                child: Text(
                                  message.content,
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                  color: const Color(0xC5000000),
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Microphone button
                  Container(
                    decoration: BoxDecoration(
                      color: _isListening ? Colors.red.withOpacity(0.1) : const Color(0xFFD0ECE8).withOpacity(0.3),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.red : const Color(0xFF6BBFB5),
                      ),
                      onPressed: () {
                        if (_isListening) {
                          _stopListening();
                        } else {
                          _startListening();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD0ECE8).withOpacity(0.3),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: _isListening ? 'Listening...' : 'Type a message...',
                          hintStyle: GoogleFonts.poppins(
                            color: const Color(0x80000000),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: const Color(0xC5000000),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
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
