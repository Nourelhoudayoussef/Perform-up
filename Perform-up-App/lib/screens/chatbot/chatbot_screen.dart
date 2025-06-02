import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:convert';
import '../../services/chatbot_service.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class ChatbotScreen extends StatefulWidget {
  const ChatbotScreen({Key? key}) : super(key: key);

  @override
  State<ChatbotScreen> createState() => _ChatbotScreenState();
}

class _ChatbotScreenState extends State<ChatbotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final ChatbotService _chatbotService = ChatbotService();
  bool _isLoading = false;
  bool _isLoadingHistory = true;

  // Speech to text variables
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    _initSpeech();
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
          localeId: 'en_US', // You can change this to support other languages
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload chat history when returning to this screen
    _loadChatHistory();
  }

  

  // Load chat history from the API
  Future<void> _loadChatHistory() async {
    setState(() {
      _isLoadingHistory = true;
    });

    try {
      final conversations = await _chatbotService.getChatHistory();
      
      if (conversations.isNotEmpty) {
        setState(() {
          _messages.clear();
          
          // Sort conversations by timestamp in reverse order (newest first)
          conversations.sort((a, b) {
            final aTime = a['timestamp'] ?? '';
            final bTime = b['timestamp'] ?? '';
            return bTime.compareTo(aTime); // Newest first
          });
          
          for (var conversation in conversations) {
            final timestamp = conversation['timestamp'] ?? '';
            print('Adding conversation from: $timestamp');
            print('Conversation data: ${json.encode(conversation)}'); // Debug log
            
            // Check types of question and response
            print('Question type: ${conversation['question'].runtimeType}');
            print('Response type: ${conversation['response'].runtimeType}');
            
            // Add user question
            _messages.add(ChatMessage(
              text: conversation['question'] is String ? conversation['question'] : json.encode(conversation['question']),
              isUser: true,
            ));
            
            // Add chatbot response
            _messages.add(ChatMessage(
              text: conversation['response'] is String ? conversation['response'] : json.encode(conversation['response']),
              isUser: false,
            ));
          }
        });
      } else {
        _addWelcomeMessage();
      }
    } catch (e) {
      print('Error loading chat history: $e');
      // If there's an error, show welcome message
    _addWelcomeMessage();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load chat history. Starting a new conversation.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      setState(() {
        _isLoadingHistory = false;
      });
      _scrollToBottom();
    }
  }

  void _addWelcomeMessage() {
    setState(() {
      _messages.add(
        const ChatMessage(
          text: "Hello! I'm your factory assistant. Ask me about production data, efficiency metrics, or any other information about your factory operations.",
          isUser: false,
        ),
      );
    });
  }

  @override
  void dispose() {
    _stopListening();
    _speech.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSubmitted(String text) async {
    if (text.trim().isEmpty) return;

    _messageController.clear();
    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isUser: true,
        ),
      );
      _isLoading = true;
    });

    // Scroll to bottom
    _scrollToBottom();

    try {
      // Call the chatbot service
      final response = await _chatbotService.sendMessage(text);
      
      setState(() {
        _messages.add(
          ChatMessage(
            text: response,
            isUser: false,
          ),
        );
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add(
          ChatMessage(
            text: "Sorry, I couldn't process your request. Please try again later.",
            isUser: false,
          ),
        );
        _isLoading = false;
      });
    }

    // Scroll to bottom again after adding response
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0.0); // Scroll to top since list is reversed
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD0ECE8),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6BBFB5).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.smart_toy,
                color: Color(0xFF6BBFB5),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'AI Assistant',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: const Color(0xC5000000),
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xC5000000)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoadingHistory
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF6BBFB5),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    reverse: true,
                    itemBuilder: (context, index) {
                      final message = _messages[_messages.length - 1 - index];
                      return message;
                    },
                  ),
          ),
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6BBFB5).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.smart_toy,
                      color: Color(0xFF6BBFB5),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Thinking...",
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF6BBFB5),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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
                          hintText: _isListening ? 'Listening...' : 'Type your message...',
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
                        onSubmitted: _handleSubmitted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: const Color(0xFF6BBFB5),
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      onTap: () => _handleSubmitted(_messageController.text),
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

class ChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;

  const ChatMessage({
    Key? key,
    required this.text,
    required this.isUser,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFD0ECE8) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 0),
            bottomRight: Radius.circular(isUser ? 0 : 16),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6BBFB5).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.smart_toy,
                  color: Color(0xFF6BBFB5),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                text,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: const Color(0xC5000000),
                ),
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6BBFB5).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person,
                  color: Color(0xFF6BBFB5),
                  size: 20,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
} 