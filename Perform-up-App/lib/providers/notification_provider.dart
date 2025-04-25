import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../models/notification_model.dart';

enum AlertType {
  emergencyAlert,
  efficiencyDropAlert,
  productionDelayAlert,
  machineFailure,
  urgentMeeting,
}

enum RecipientType {
  managersAndSupervisors,
  technicians,
  everyone,
}

class NotificationProvider extends ChangeNotifier {
  bool isReceived = true; // Toggle between received and send views
  AlertType? selectedAlertType;
  RecipientType? selectedRecipient;
  int? selectedWorkshop;
  int? selectedChaine;
  final ApiService _apiService = ApiService();
  String? _userRole;

  NotificationProvider() {
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    if (_userRole != null) return;
    final prefs = await SharedPreferences.getInstance();
    _userRole = prefs.getString('role')?.toUpperCase();
    notifyListeners();
  }

  String? get userRole => _userRole;

  void setRole(String role) {
    _userRole = role.toUpperCase();
    // Force technicians to received view
    if (_userRole == 'TECHNICIAN') {
      isReceived = true;
    }
    notifyListeners();
  }

  bool get canSendNotifications {
    return _userRole == 'MANAGER' || _userRole == 'SUPERVISOR';
  }

  bool get isManager => _userRole == 'MANAGER';
  bool get isSupervisor => _userRole == 'SUPERVISOR';
  bool get isTechnician => _userRole == 'TECHNICIAN';

  // List of received notifications
  List<NotificationModel> receivedNotifications = [];

  Future<void> loadReceivedNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('userId');
      if (userId == null) throw Exception('User ID not found');
      
      final notifications = await _apiService.getReceivedNotifications(userId);
      receivedNotifications = notifications;
      notifyListeners();
    } catch (e) {
      print('Error loading notifications: $e');
      throw Exception('Failed to load notifications');
    }
  }

  void toggleView() {
    // Technicians should only be able to view received notifications
    if (_userRole == 'TECHNICIAN') {
      isReceived = true;
      return;
    }
    // Only allow toggle if user has permission to send notifications
    if (canSendNotifications) {
      isReceived = !isReceived;
      notifyListeners();
    }
  }

  void setAlertType(AlertType type) {
    // Block technicians from setting alert type
    if (isTechnician) return;
    
    if (!canSendNotifications) return;
    
    selectedAlertType = type;
    // Reset recipient based on alert type and user role
    if (isManager) {
      // Managers can only send urgent meeting notifications to managers and supervisors
      if (type == AlertType.urgentMeeting) {
        selectedRecipient = RecipientType.managersAndSupervisors;
      }
    } else if (isSupervisor) {
      // Supervisors can send different types of notifications
      if (type == AlertType.machineFailure) {
        selectedRecipient = RecipientType.technicians;
      } else if (type == AlertType.efficiencyDropAlert || type == AlertType.productionDelayAlert) {
        selectedRecipient = RecipientType.managersAndSupervisors;
      } else if (type == AlertType.emergencyAlert) {
        selectedRecipient = RecipientType.everyone;
      }
    }
    notifyListeners();
  }

  void setRecipient(RecipientType type) {
    // Block technicians from setting recipient
    if (isTechnician) return;
    
    if (!canSendNotifications) return;
    
    if (canSelectRecipient(type)) {
      selectedRecipient = type;
      notifyListeners();
    }
  }

  void setWorkshop(int number) {
    // Block technicians from setting workshop
    if (isTechnician) return;
    
    if (!canSendNotifications) return;
    
    selectedWorkshop = number;
    notifyListeners();
  }

  void setChaine(int number) {
    // Block technicians from setting chain
    if (isTechnician) return;
    
    if (!canSendNotifications) return;
    
    selectedChaine = number;
    notifyListeners();
  }

  bool canSelectRecipient(RecipientType type) {
    if (!canSendNotifications) return false;

    if (isManager) {
      // Managers can only send to managers and supervisors
      return type == RecipientType.managersAndSupervisors && 
             selectedAlertType == AlertType.urgentMeeting;
    } else if (isSupervisor) {
      // Supervisors can send to different recipients based on alert type
      if (selectedAlertType == AlertType.emergencyAlert) {
        return true; // Can send to everyone
      } else if (selectedAlertType == AlertType.machineFailure) {
        return type == RecipientType.technicians;
      } else if (selectedAlertType == AlertType.efficiencyDropAlert || 
                 selectedAlertType == AlertType.productionDelayAlert) {
        return type == RecipientType.managersAndSupervisors;
      }
    }
    return false;
  }

  Future<void> sendNotification() async {
    // First check if user is a technician
    if (isTechnician) {
      throw Exception('Technicians cannot send notifications');
    }

    // Then check general permission
    if (!canSendNotifications) {
      throw Exception('You do not have permission to send notifications');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final senderId = prefs.getString('userId');
      if (senderId == null) throw Exception('User ID not found');

      if (isManager) {
        if (selectedAlertType == AlertType.urgentMeeting) {
          await sendUrgentMeetingNotification(
            "Urgent Meeting Call",
            "Please join the urgent meeting immediately",
            senderId
          );
        } else {
          throw Exception('Managers can only send urgent meeting notifications');
        }
      } else if (isSupervisor) {
        switch (selectedAlertType) {
          case AlertType.machineFailure:
            await _apiService.sendMachineFailureNotification(
              "Machine Failure Alert",
              "Attention required: Machine failure reported in Workshop $selectedWorkshop, Chaine $selectedChaine",
              senderId
            );
            break;
          case AlertType.productionDelayAlert:
            await _apiService.sendProductionDelayNotification(
              "Production Delay Alert",
              "Production delay reported in Workshop $selectedWorkshop, Chaine $selectedChaine",
              senderId
            );
            break;
          case AlertType.efficiencyDropAlert:
            await _apiService.sendEfficiencyDropNotification(
              "Efficiency Drop Alert",
              "Efficiency drop detected in Workshop $selectedWorkshop, Chaine $selectedChaine",
              senderId
            );
            break;
          case AlertType.emergencyAlert:
            await _apiService.sendEmergencyNotification(
              "Emergency Alert",
              "Emergency situation in Workshop $selectedWorkshop, Chaine $selectedChaine",
              senderId
            );
            break;
          default:
            throw Exception('Invalid alert type selected');
        }
      }

      // Reset form after successful send
      selectedAlertType = null;
      selectedRecipient = null;
      selectedWorkshop = null;
      selectedChaine = null;
      notifyListeners();
    } catch (e) {
      print('Error sending notification: $e');
      throw Exception('Failed to send notification: ${e.toString()}');
    }
  }

  Future<void> sendUrgentMeetingNotification(String title, String message, String senderId) async {
    if (!isManager) {
      throw Exception('Only managers can send urgent meeting notifications');
    }
    try {
      await _apiService.sendUrgentMeetingNotification(title, message, senderId);
      // Reset form after sending
      selectedAlertType = null;
      selectedRecipient = null;
      selectedWorkshop = null;
      selectedChaine = null;
      notifyListeners();
    } catch (e) {
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  // Add a new notification from WebSocket
  void addNewNotification(NotificationModel notification) {
    // Check if the notification is not already in the list
    if (!receivedNotifications.any((n) => n.id == notification.id)) {
      receivedNotifications.add(notification);
      
      // Sort notifications by creation date (newest first)
      receivedNotifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
      notifyListeners();
    }
  }
} 