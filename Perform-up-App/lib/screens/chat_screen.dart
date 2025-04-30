import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/websocket_service.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatScreen extends StatefulWidget {
  final String receiverId;
  final String receiverName;

  ChatScreen({
    Key? key,
    required this.receiverId,
    required this.receiverName,
  }) : super(key: key) {
    print('[ChatScreen] CONSTRUCTOR called for receiverId: ' + receiverId);
  }

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final WebSocketService _webSocketService = WebSocketService();
  final ApiService _apiService = ApiService();
  final ScrollController _scrollController = ScrollController();
  String? _currentUserId;
  List<Message> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    print('[ChatScreen] initState called');
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    print('[ChatScreen] _initializeChat called');
    try {
      print('[ChatScreen] _initializeChat: Getting SharedPreferences');
      final prefs = await SharedPreferences.getInstance();
      print('[ChatScreen] _initializeChat: Got SharedPreferences');
      _currentUserId = prefs.getString('userId');
      print('[ChatScreen] _initializeChat: currentUserId = ' + (_currentUserId ?? 'null'));
      print('[ChatScreen] _initializeChat: receiverId = ' + widget.receiverId);

      print('[ChatScreen] _initializeChat: Loading messages');
      final messages = await _apiService.getIndividualMessages(_currentUserId!, widget.receiverId);
      print('[ChatScreen] _initializeChat: Loaded messages, count = ' + messages.length.toString());
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }

      final chatGroupId = _webSocketService.generateChatGroupId(_currentUserId!, widget.receiverId);
      print('[ChatScreen] _initializeChat: Setting onConnectedCallback');
      _webSocketService.setOnConnectedCallback(() {
        print('[ChatScreen] onConnectedCallback triggered');
        print('[ChatScreen] Calling subscribeToChatGroup with chatGroupId: ' + chatGroupId);
        _webSocketService.subscribeToChatGroup(chatGroupId);
      });
      print('[ChatScreen] _initializeChat: Calling connect()');
      await _webSocketService.connect();
      print('[ChatScreen] _initializeChat: connect() finished');
    } catch (e) {
      print('[ChatScreen] _initializeChat: Caught error: ' + e.toString());
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading messages: $e')),
        );
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final content = _messageController.text.trim();
    _messageController.clear();

    try {
      // Send message via REST API
      final message = await _apiService.sendIndividualMessage(
        _currentUserId!,
        widget.receiverId,
        content,
      );

      // Also send via WebSocket for real-time delivery
      await _webSocketService.sendChatMessage(widget.receiverId, content);

      if (mounted) {
        setState(() {
          _messages.insert(0, message);
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('[ChatScreen] build called');
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.receiverName),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    children: [
                      StreamBuilder<Message>(
                        stream: _webSocketService.chatMessageStream,
                        builder: (context, snapshot) {
                          print('[ChatScreen] StreamBuilder builder called. hasData: [32m${snapshot.hasData}[0m');
                          if (snapshot.hasData) {
                            final message = snapshot.data!;
                            print('[ChatScreen] StreamBuilder received message: ' + message.toJson().toString());
                            // Only add the message if it belongs to this chat and isn't already in the list
                            if (message.chatGroupId == _webSocketService.generateChatGroupId(_currentUserId!, widget.receiverId) &&
                                !_messages.any((m) => m.id == message.id)) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) {
                                  setState(() {
                                    _messages.insert(0, message);
                                  });
                                  _scrollToBottom();
                                }
                              });
                            }
                          }
                          return ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final message = _messages[index];
                              final isMe = message.senderId == _currentUserId;
                              return MessageBubble(
                                message: message,
                                isMe: isMe,
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;

  const MessageBubble({
    Key? key,
    required this.message,
    required this.isMe,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        decoration: BoxDecoration(
          color: isMe ? Colors.blue : Colors.grey[300],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content,
              style: TextStyle(
                color: isMe ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message.senderName,
              style: TextStyle(
                color: isMe ? Colors.white70 : Colors.black54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
} 