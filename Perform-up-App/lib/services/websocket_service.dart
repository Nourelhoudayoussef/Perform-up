import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../models/message.dart';
import '../models/notification_model.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  
  WebSocketService._internal();
  
  // Backend WebSocket URL
  static const String _webSocketUrl = 'ws://10.0.2.2:8080/ws';
  
  // WebSocket channel instance
  WebSocketChannel? _channel;
  bool _isConnected = false;
  
  // Stream controllers
  final _notificationStreamController = StreamController<NotificationModel>.broadcast();
  final _chatMessageStreamController = StreamController<Message>.broadcast();
  StreamSubscription? _subscription;
  
  // Streams that UI can listen to
  Stream<NotificationModel> get notificationStream => _notificationStreamController.stream;
  Stream<Message> get chatMessageStream => _chatMessageStreamController.stream;
  
  // Connection state
  bool get isConnected => _isConnected;
  
  // Initialize and connect to the WebSocket server
  Future<void> connect() async {
    if (_channel != null) {
      // If already connected, return
      if (_isConnected) return;
      
      // If previously initialized but disconnected, reconnect
      _connectToWebSocket();
      return;
    }
    
    await _connectToWebSocket();
  }
  
  // Connect to WebSocket
  Future<void> _connectToWebSocket() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final userId = prefs.getString('userId');
      
      if (token == null || userId == null) {
        throw Exception('Missing authentication data');
      }
      
      final uri = Uri.parse('$_webSocketUrl?token=$token&userId=$userId');
      _channel = WebSocketChannel.connect(uri);
      
      // Listen to incoming messages
      _subscription = _channel!.stream.listen(
        _handleIncomingMessage,
        onDone: _handleDisconnect,
        onError: _handleError,
      );
      
      _isConnected = true;
      print('Connected to WebSocket server');
      
      // Subscribe to specific topics - send subscription messages
      _subscribeToUserNotifications(userId);
      _subscribeToUserChats(userId);
    } catch (e) {
      print('Error connecting to WebSocket: $e');
      _isConnected = false;
    }
  }
  
  // Handle incoming WebSocket messages
  void _handleIncomingMessage(dynamic message) {
    try {
      final data = json.decode(message);
      
      // Check message type to determine how to process it
      if (data['type'] == 'notification') {
        final notification = NotificationModel.fromJson(data['payload']);
        _notificationStreamController.add(notification);
      } else if (data['type'] == 'chat') {
        final chatMessage = Message.fromJson(data['payload']);
        _chatMessageStreamController.add(chatMessage);
      } else {
        print('Unknown message type: ${data['type']}');
      }
    } catch (e) {
      print('Error processing WebSocket message: $e');
    }
  }
  
  // Handle WebSocket disconnect
  void _handleDisconnect() {
    print('Disconnected from WebSocket server');
    _isConnected = false;
  }
  
  // Handle WebSocket error
  void _handleError(error) {
    print('WebSocket error: $error');
    _isConnected = false;
  }
  
  // Subscribe to user notifications
  void _subscribeToUserNotifications(String userId) {
    if (_channel == null || !_isConnected) return;
    
    _channel!.sink.add(json.encode({
      'action': 'subscribe',
      'topic': 'notifications',
      'userId': userId
    }));
  }
  
  // Subscribe to user chats
  void _subscribeToUserChats(String userId) {
    if (_channel == null || !_isConnected) return;
    
    _channel!.sink.add(json.encode({
      'action': 'subscribe',
      'topic': 'chat',
      'userId': userId
    }));
  }
  
  // Subscribe to a specific group chat
  Future<void> subscribeToGroupChat(String groupId) async {
    if (_channel == null || !_isConnected) {
      print('Cannot subscribe to group chat: not connected');
      return;
    }
    
    _channel!.sink.add(json.encode({
      'action': 'subscribe',
      'topic': 'groupChat',
      'groupId': groupId
    }));
  }
  
  // Send a chat message
  Future<void> sendChatMessage(String receiverId, String content) async {
    if (_channel == null || !_isConnected) return;
    
    final prefs = await SharedPreferences.getInstance();
    final senderId = prefs.getString('userId');
    
    if (senderId == null) return;
    
    _channel!.sink.add(json.encode({
      'action': 'chat',
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content
    }));
  }
  
  // Send a group chat message
  Future<void> sendGroupMessage(String groupId, String content) async {
    if (_channel == null || !_isConnected) return;
    
    final prefs = await SharedPreferences.getInstance();
    final senderId = prefs.getString('userId');
    
    if (senderId == null) return;
    
    _channel!.sink.add(json.encode({
      'action': 'groupChat',
      'senderId': senderId,
      'groupId': groupId,
      'content': content
    }));
  }
  
  // Disconnect from the WebSocket server
  void disconnect() {
    _subscription?.cancel();
    _channel?.sink.close(status.goingAway);
    _isConnected = false;
  }
  
  // Dispose of resources
  void dispose() {
    disconnect();
    _notificationStreamController.close();
    _chatMessageStreamController.close();
  }
} 