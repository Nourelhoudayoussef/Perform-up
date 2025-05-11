import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

class ConfigService {
  // Development URLs
  static const String _devBaseUrl = 'http://192.168.3.128:8080';
  static const String _devWebSocketUrl = 'ws://192.168.3.128:8080/ws';
  
  // Staging URLs
  static const String _stagingBaseUrl = 'https://staging-api.performup.com';
  static const String _stagingWebSocketUrl = 'wss://staging-api.performup.com/ws';
  
  // Production URLs
  static const String _prodBaseUrl = 'https://api.performup.com';
  static const String _prodWebSocketUrl = 'wss://api.performup.com/ws';

  static String get baseUrl {
    if (kDebugMode) {
      // Development environment
      if (Platform.isAndroid) {
        return 'http://192.168.3.128:8080';//emulator
      } else if (Platform.isIOS) {
        return 'http://localhost:8080';
      }
      return _devBaseUrl;
    } else if (kProfileMode) {
      return _stagingBaseUrl;
    } else {
      return _prodBaseUrl;
    }
  }

  static String get webSocketUrl {
    if (kDebugMode) {
      // Development environment
      if (Platform.isAndroid) {
        return 'ws://192.168.3.128:8080/ws/websocket';  // Added /websocket for STOMP
      } else if (Platform.isIOS) {
        return 'ws://localhost:8080/ws/websocket';
      }
      return _devWebSocketUrl + '/websocket';
    } else if (kProfileMode) {
      return _stagingWebSocketUrl + '/websocket';
    } else {
      return _prodWebSocketUrl + '/websocket';
    }
  }

  // Add debug logging
  static void logConfiguration() {
    print('Current Environment: ${kDebugMode ? 'Debug' : kProfileMode ? 'Profile' : 'Release'}');
    print('Base URL: $baseUrl');
    print('WebSocket URL: $webSocketUrl');
    print('Platform: ${Platform.isAndroid ? 'Android' : Platform.isIOS ? 'iOS' : 'Other'}');
  }
} 