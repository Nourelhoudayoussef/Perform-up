import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stomp_dart_client/stomp.dart';
import 'package:stomp_dart_client/stomp_config.dart';
import 'package:stomp_dart_client/stomp_frame.dart';
import '../models/message.dart';
import '../models/notification_model.dart';
import 'dart:io' show Platform;
import 'package:logger/logger.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  
  WebSocketService._internal();
  
  final Logger _logger = Logger();
  StompClient? _stompClient;
  Timer? _pingTimer;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  bool _isReconnecting = false;
  Duration _reconnectInterval = const Duration(seconds: 5);
  
  // Stream controllers
  final _notificationStreamController = StreamController<NotificationModel>.broadcast();
  final _chatMessageStreamController = StreamController<Message>.broadcast();
  final StreamController<bool> _connectionStatusController = StreamController<bool>.broadcast();
  
  // Streams that UI can listen to
  Stream<NotificationModel> get notificationStream => _notificationStreamController.stream;
  Stream<Message> get chatMessageStream => _chatMessageStreamController.stream;
  
  // Connection state
  bool get isConnected => _isConnected;
  
  String? _currentChatGroupId;
  
  void Function()? _chatSubscription;
  
  VoidCallback? _onConnectedCallback;
  
  dynamic _pingSubscription;
  
  void setOnConnectedCallback(VoidCallback callback) {
    print('[WebSocketService] setOnConnectedCallback called');
    _onConnectedCallback = callback;
  }
  
  // Initialize and connect to the WebSocket server
  Future<void> connect() async {
    print('[WebSocketService] connect() called');
    if (_stompClient?.connected ?? false) {
      print('[WebSocketService] Already connected');
      if (_onConnectedCallback != null) {
        print('[WebSocketService] Calling onConnectedCallback (already connected)');
        _onConnectedCallback!();
      }
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final userId = prefs.getString('userId');

      if (token == null || userId == null) {
        throw Exception('Token or userId not found in SharedPreferences');
      }

      print('[WebSocketService] Connecting with token and userId');
      _stompClient = StompClient(
        config: StompConfig(
          url: _webSocketUrl,
          onConnect: _onConnect,
          onDisconnect: _onDisconnect,
          onWebSocketError: _onWebSocketError,
          onStompError: _onStompError,
          onDebugMessage: (msg) => _logger.d('STOMP Debug: $msg'),
          stompConnectHeaders: {
            'Authorization': 'Bearer $token',
            'userId': userId,
          },
          webSocketConnectHeaders: {
            'Authorization': 'Bearer $token',
            'userId': userId,
          },
          connectionTimeout: const Duration(seconds: 10),
          heartbeatIncoming: const Duration(seconds: 0),
          heartbeatOutgoing: const Duration(seconds: 10),
          reconnectDelay: const Duration(seconds: 5),
        ),
      );

      _stompClient?.activate();
      _startPingTimer();
    } catch (e) {
      _logger.e('Error connecting to WebSocket: $e');
      rethrow;
    }
  }
  
  // Get appropriate WebSocket URL based on platform
  String get _webSocketUrl {
    if (Platform.isAndroid) {
      return 'ws://10.0.2.2:8080/ws';
    } else if (Platform.isIOS) {
      return kIsWeb ? 'ws://localhost:8080/ws' : 'ws://localhost:8080/ws';
    }
    return 'ws://10.0.2.2:8080/ws';
  }
  
  void _onConnect(StompFrame frame) {
    _logger.i('Connected to WebSocket server');
    print('[WebSocketService] Connected to WebSocket server');
    _isConnected = true;
    _isReconnecting = false;
    _connectionStatusController.add(true);
    
    if (_onConnectedCallback != null) {
      print('[WebSocketService] Calling onConnectedCallback');
      _onConnectedCallback!();
    }
    
    if (_currentChatGroupId != null) {
      print('[WebSocketService] Resubscribing to chat group: $_currentChatGroupId');
      subscribeToChatGroup(_currentChatGroupId!);
    }
  }
  
  void _onDisconnect(StompFrame frame) {
    _logger.i('Disconnected from WebSocket server');
    print('[WebSocketService] Disconnected from WebSocket server');
    _isConnected = false;
    _connectionStatusController.add(false);
    _scheduleReconnect();
  }
  
  void _onWebSocketError(dynamic error) {
    _logger.e('WebSocket error: $error');
    print('[WebSocketService] WebSocket error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }
  
  void _onStompError(StompFrame frame) {
    _logger.e('STOMP error: ${frame.body}');
    print('[WebSocketService] STOMP error: ${frame.body}');
    _isConnected = false;
    _scheduleReconnect();
  }
  
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_stompClient?.connected ?? false) {
        _stompClient?.send(
          destination: '/app/ping',
          body: 'ping',
        );
      }
    });
  }
  
  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }
  
  void _scheduleReconnect() {
    if (_isReconnecting) return;
    _isReconnecting = true;
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectInterval, () async {
      _isReconnecting = false;
      try {
        print('[WebSocketService] Attempting to reconnect...');
        await connect();
      } catch (e) {
        _logger.e('Failed to reconnect: $e');
        final nextDelay = Duration(seconds: _reconnectInterval.inSeconds * 2);
        print('[WebSocketService] Reconnection failed, will retry in ${nextDelay.inSeconds} seconds');
        _reconnectTimer = Timer(nextDelay, () {
          _isReconnecting = false;
          _scheduleReconnect();
        });
      }
    });
  }
  
  Future<void> sendChatMessage(String receiverId, String content) async {
    if (!_isConnected) {
      print('[WebSocketService] Not connected, attempting to connect...');
      await connect();
    }
    
    final prefs = await SharedPreferences.getInstance();
    final senderId = prefs.getString('userId');
    final senderName = prefs.getString('username') ?? 'Unknown User';
    
    if (senderId == null) {
      throw Exception('User ID not found in SharedPreferences');
    }

    final message = {
      'senderId': senderId,
      'receiverId': receiverId,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'senderName': senderName,
    };

    print('[WebSocketService] Sending message to /app/chat: ${jsonEncode(message)}');
    _stompClient?.send(
      destination: '/app/chat',
      body: jsonEncode(message),
    );
  }
  
  Future<void> sendGroupMessage(String groupId, String content) async {
    if (!_isConnected) {
      print('[WebSocketService] Not connected, attempting to connect...');
      await connect();
    }
    
    final prefs = await SharedPreferences.getInstance();
    final senderId = prefs.getString('userId');
    final senderName = prefs.getString('username') ?? 'Unknown User';
    
    if (senderId == null) {
      throw Exception('User ID not found in SharedPreferences');
    }

    final message = {
      'senderId': senderId,
      'chatGroupId': groupId,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
      'senderName': senderName,
    };

    print('[WebSocketService] Sending group message to /app/group-chat: ${jsonEncode(message)}');
    _stompClient?.send(
      destination: '/app/group-chat',
      body: jsonEncode(message),
    );
  }
  
  void subscribeToGroupChat(String groupId) {
    print('[WebSocketService] subscribeToGroupChat called with: $groupId');
    print('[WebSocketService] Current connection status: ${_stompClient?.connected ?? false}');
    
    if (!_isConnected) {
      print('[WebSocketService] Not connected, cannot subscribe');
      throw Exception('WebSocket is not connected');
    }

    // Unsubscribe from previous chat group topic if exists
    if (_chatSubscription != null) {
      print('[WebSocketService] Unsubscribing from previous chat group');
      _chatSubscription!();
      _chatSubscription = null;
    }

    print('[WebSocketService] Subscribing to /topic/chat/$groupId');
    _chatSubscription = _stompClient?.subscribe(
      destination: '/topic/chat/$groupId',
      callback: (frame) {
        print('[WebSocketService] Group chat frame received for topic /topic/chat/$groupId');
        print('[WebSocketService] Frame body: ${frame.body}');
        if (frame.body != null) {
          try {
            final message = Message.fromJson(jsonDecode(frame.body!));
            print('[WebSocketService] Adding message to chatMessageStreamController: ${message.toJson()}');
            _chatMessageStreamController.add(message);
          } catch (e) {
            print('[WebSocketService] Error parsing message: $e');
          }
        }
      },
    );
    print('[WebSocketService] Subscription to /topic/chat/$groupId created.');
  }
  
  // Subscribe to chat messages for a specific chat group
  void subscribeToChatGroup(String chatGroupId) {
    print('[WebSocketService] subscribeToChatGroup called with: $chatGroupId');
    print('[WebSocketService] Current connection status: ${_stompClient?.connected ?? false}');
    
    if (!_isConnected) {
      print('[WebSocketService] Not connected, cannot subscribe');
      throw Exception('WebSocket is not connected');
    }

    // Unsubscribe from previous chat group topic
    _chatSubscription?.call();
    
    print('[WebSocketService] Subscribing to /topic/chat/$chatGroupId');
    _chatSubscription = _stompClient?.subscribe(
      destination: '/topic/chat/$chatGroupId',
      callback: (frame) {
        print('[WebSocketService] Chat frame received for topic /topic/chat/$chatGroupId');
        print('[WebSocketService] Frame body: ${frame.body}');
        if (frame.body != null) {
          try {
            final message = Message.fromJson(jsonDecode(frame.body!));
            print('[WebSocketService] Adding message to chatMessageStreamController: ${message.toJson()}');
            _chatMessageStreamController.add(message);
          } catch (e) {
            print('[WebSocketService] Error parsing message: $e');
          }
        }
      },
    );
    print('[WebSocketService] Subscription to /topic/chat/$chatGroupId created.');
  }
  
  // Disconnect from WebSocket
  void disconnect() {
    _stopPingTimer();
    _reconnectTimer?.cancel();
    _stompClient?.deactivate();
    _stompClient = null;
    _isConnected = false;
  }
  
  void dispose() {
    disconnect();
    _notificationStreamController.close();
    _chatMessageStreamController.close();
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _pingSubscription?.unsubscribe();
    _connectionStatusController.close();
  }
  
  // Optionally, expose a helper to generate the chat group ID (same as backend)
  String generateChatGroupId(String userId1, String userId2) {
    final ids = [userId1, userId2]..sort();
    return 'individual_${ids[0]}_${ids[1]}';
  }

  // Add connection status monitoring
  Stream<bool> get connectionStatus => _connectionStatusController.stream;

  // Add method to check connection health
  Future<bool> checkConnectionHealth() async {
    if (!_isConnected) return false;
    
    try {
      // Send a ping message and wait for response
      final completer = Completer<bool>();
      
      // Unsubscribe from any existing ping subscription
      _pingSubscription?.unsubscribe();
      
      _pingSubscription = _stompClient?.subscribe(
        destination: '/user/queue/ping',
        callback: (frame) {
          completer.complete(true);
        },
      );

      // Send ping
      _stompClient?.send(
        destination: '/app/ping',
        body: jsonEncode({'timestamp': DateTime.now().millisecondsSinceEpoch}),
      );

      // Wait for response with timeout
      final result = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );

      _pingSubscription?.unsubscribe();
      return result;
    } catch (e) {
      _logger.e('Connection health check failed: $e');
      return false;
    }
  }

  void subscribeToNotifications(String userId) {
    print('[WebSocketService] subscribeToNotifications called with: $userId');
    print('[WebSocketService] Current connection status: ${_stompClient?.connected ?? false}');
    
    if (!_isConnected) {
      print('[WebSocketService] Not connected, attempting to connect...');
      connect();
      return;
    }

    print('[WebSocketService] Subscribing to /topic/notifications/$userId');
    _stompClient?.subscribe(
      destination: '/topic/notifications/$userId',
      callback: (frame) {
        print('[WebSocketService] Notification frame received');
        print('[WebSocketService] Frame body: ${frame.body}');
        if (frame.body != null) {
          try {
            final notification = NotificationModel.fromJson(jsonDecode(frame.body!));
            print('[WebSocketService] Adding notification to notificationStreamController: ${notification.toJson()}');
            _notificationStreamController.add(notification);
          } catch (e) {
            print('[WebSocketService] Error parsing notification: $e');
          }
        }
      },
    );

    // Also subscribe to global notification types
    print('[WebSocketService] Subscribing to global notification topics');
    _stompClient?.subscribe(
      destination: '/topic/notifications/type/urgent_meeting',
      callback: (frame) {
        if (frame.body != null) {
          try {
            final notification = NotificationModel.fromJson(jsonDecode(frame.body!));
            _notificationStreamController.add(notification);
          } catch (e) {
            print('[WebSocketService] Error parsing urgent meeting notification: $e');
          }
        }
      },
    );

    _stompClient?.subscribe(
      destination: '/topic/notifications/type/machine_failure',
      callback: (frame) {
        if (frame.body != null) {
          try {
            final notification = NotificationModel.fromJson(jsonDecode(frame.body!));
            _notificationStreamController.add(notification);
          } catch (e) {
            print('[WebSocketService] Error parsing machine failure notification: $e');
          }
        }
      },
    );

    _stompClient?.subscribe(
      destination: '/topic/notifications/type/production_delay',
      callback: (frame) {
        if (frame.body != null) {
          try {
            final notification = NotificationModel.fromJson(jsonDecode(frame.body!));
            _notificationStreamController.add(notification);
          } catch (e) {
            print('[WebSocketService] Error parsing production delay notification: $e');
          }
        }
      },
    );

    _stompClient?.subscribe(
      destination: '/topic/notifications/type/efficiency_drop',
      callback: (frame) {
        if (frame.body != null) {
          try {
            final notification = NotificationModel.fromJson(jsonDecode(frame.body!));
            _notificationStreamController.add(notification);
          } catch (e) {
            print('[WebSocketService] Error parsing efficiency drop notification: $e');
          }
        }
      },
    );

    _stompClient?.subscribe(
      destination: '/topic/notifications/type/emergency',
      callback: (frame) {
        if (frame.body != null) {
          try {
            final notification = NotificationModel.fromJson(jsonDecode(frame.body!));
            _notificationStreamController.add(notification);
          } catch (e) {
            print('[WebSocketService] Error parsing emergency notification: $e');
          }
        }
      },
    );
  }
} 