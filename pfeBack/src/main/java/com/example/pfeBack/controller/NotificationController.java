package com.example.pfeBack.controller;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.CrossOrigin;

import com.example.pfeBack.dto.NotificationRequest;
import com.example.pfeBack.model.Notification;
import com.example.pfeBack.model.Role;
import com.example.pfeBack.model.User;
import com.example.pfeBack.repository.UserRepository;
import com.example.pfeBack.service.NotificationService;

@RestController
@RequestMapping("/notifications")
@CrossOrigin(origins = "*")
public class NotificationController {

    @Autowired
    private NotificationService notificationService;
    
    @Autowired
    private UserRepository userRepository;
    
    @PostMapping("/send")
    public ResponseEntity<?> sendNotification(@RequestBody Map<String, Object> request) {
        try {
            String title = (String) request.get("title");
            String message = (String) request.get("message");
            String type = (String) request.get("type");
            String senderId = (String) request.get("senderId");
            @SuppressWarnings("unchecked")
            List<String> recipientIds = (List<String>) request.get("recipientIds");

            if (!notificationService.isUserAuthorizedToSendNotification(senderId, type)) {
                return ResponseEntity.status(403).body("User not authorized to send this type of notification");
            }

            Notification notification = notificationService.createNotification(title, message, type, senderId, recipientIds);
            return ResponseEntity.ok(notification);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Error sending notification: " + e.getMessage());
        }
    }
    
    @GetMapping("/user/{userId}")
    public ResponseEntity<List<Notification>> getUserNotifications(@PathVariable String userId) {
        List<Notification> notifications = notificationService.getNotificationsForUser(userId);
        return ResponseEntity.ok(notifications);
    }
    
    @GetMapping("/unread/{userId}")
    public ResponseEntity<List<Notification>> getUnreadNotifications(@PathVariable String userId) {
        List<Notification> notifications = notificationService.getUnreadNotificationsForUser(userId);
        return ResponseEntity.ok(notifications);
    }
    
    @GetMapping("/sent/{senderId}")
    public ResponseEntity<List<Notification>> getSentNotifications(@PathVariable String senderId) {
        List<Notification> notifications = notificationService.getSentNotifications(senderId);
        return ResponseEntity.ok(notifications);
    }
    
    @PutMapping("/{notificationId}/read")
    public ResponseEntity<?> markAsRead(@PathVariable String notificationId) {
        try {
            Notification notification = notificationService.markAsRead(notificationId);
            return ResponseEntity.ok(notification);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Error marking notification as read: " + e.getMessage());
        }
    }
    
    @DeleteMapping("/{notificationId}")
    public ResponseEntity<?> deleteNotification(@PathVariable String notificationId) {
        try {
            notificationService.deleteNotification(notificationId);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Error deleting notification: " + e.getMessage());
        }
    }
    
    @DeleteMapping("/user/{userId}")
    public ResponseEntity<?> deleteUserNotifications(@PathVariable String userId) {
        try {
            notificationService.deleteNotificationsForUser(userId);
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            return ResponseEntity.badRequest().body("Error deleting user notifications: " + e.getMessage());
        }
    }
    
    // Machine failure notification (Supervisor to Technicians)
    @PostMapping("/machine-failure")
    public ResponseEntity<?> sendMachineFailureNotification(@RequestBody NotificationRequest request) {
        try {
            String senderId = request.getSenderId();
            
            // Verify sender is a supervisor
            if (!isSupervisor(senderId)) {
                Map<String, String> response = new HashMap<>();
                response.put("error", "Only supervisors can send machine failure notifications");
                return ResponseEntity.status(HttpStatus.FORBIDDEN).body(response);
            }
            
            // Get all technicians as recipients
            List<String> technicianIds = notificationService.getTechnicianIds();
            
            // Create and save the notification
            Notification notification = notificationService.createNotification(
                    request.getTitle(),
                    request.getMessage(),
                    "MACHINE_FAILURE",
                    senderId,
                    technicianIds
            );
            
            return ResponseEntity.status(HttpStatus.CREATED).body(notification);
        } catch (Exception e) {
            Map<String, String> response = new HashMap<>();
            response.put("error", "Failed to send machine failure notification: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
        }
    }
    
    // Production delay notification (Supervisor to Managers)
    @PostMapping("/production-delay")
    public ResponseEntity<?> sendProductionDelayNotification(@RequestBody NotificationRequest request) {
        try {
            String senderId = request.getSenderId();
            
            // Verify sender is a supervisor
            if (!isSupervisor(senderId)) {
                Map<String, String> response = new HashMap<>();
                response.put("error", "Only supervisors can send production delay notifications");
                return ResponseEntity.status(HttpStatus.FORBIDDEN).body(response);
            }
            
            // Get all managers as recipients
            List<String> managerIds = notificationService.getManagerIds();
            
            // Create and save the notification
            Notification notification = notificationService.createNotification(
                    request.getTitle(),
                    request.getMessage(),
                    "PRODUCTION_DELAY",
                    senderId,
                    managerIds
            );
            
            return ResponseEntity.status(HttpStatus.CREATED).body(notification);
        } catch (Exception e) {
            Map<String, String> response = new HashMap<>();
            response.put("error", "Failed to send production delay notification: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
        }
    }
    
    // Efficiency drop notification (Supervisor to Managers and other Supervisors)
    @PostMapping("/efficiency-drop")
    public ResponseEntity<?> sendEfficiencyDropNotification(@RequestBody NotificationRequest request) {
        try {
            String senderId = request.getSenderId();
            
            // Verify sender is a supervisor
            if (!isSupervisor(senderId)) {
                Map<String, String> response = new HashMap<>();
                response.put("error", "Only supervisors can send efficiency drop notifications");
                return ResponseEntity.status(HttpStatus.FORBIDDEN).body(response);
            }
            
            // Get managers and supervisors as recipients
            List<String> recipients = notificationService.getManagerAndSupervisorIds();
            
            // Create and save the notification
            Notification notification = notificationService.createNotification(
                    request.getTitle(),
                    request.getMessage(),
                    "EFFICIENCY_DROP",
                    senderId,
                    recipients
            );
            
            return ResponseEntity.status(HttpStatus.CREATED).body(notification);
        } catch (Exception e) {
            Map<String, String> response = new HashMap<>();
            response.put("error", "Failed to send efficiency drop notification: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
        }
    }
    
    // Emergency notification (Supervisor to All Users)
    @PostMapping("/emergency")
    public ResponseEntity<?> sendEmergencyNotification(@RequestBody NotificationRequest request) {
        try {
            String senderId = request.getSenderId();
            
            // Verify sender is a supervisor
            if (!isSupervisor(senderId)) {
                Map<String, String> response = new HashMap<>();
                response.put("error", "Only supervisors can send emergency notifications");
                return ResponseEntity.status(HttpStatus.FORBIDDEN).body(response);
            }
            
            // Get all users as recipients
            List<String> allUserIds = notificationService.getAllUserIds();
            
            // Create and save the notification
            Notification notification = notificationService.createNotification(
                    request.getTitle(),
                    request.getMessage(),
                    "EMERGENCY",
                    senderId,
                    allUserIds
            );
            
            return ResponseEntity.status(HttpStatus.CREATED).body(notification);
        } catch (Exception e) {
            Map<String, String> response = new HashMap<>();
            response.put("error", "Failed to send emergency notification: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
        }
    }
    
    // Urgent meeting notification (Manager to Managers and Supervisors)
    @PostMapping("/urgent-meeting")
    public ResponseEntity<?> sendUrgentMeetingNotification(@RequestBody NotificationRequest request) {
        try {
            String senderId = request.getSenderId();
            System.out.println("Received urgent meeting notification request from sender ID: " + senderId);
            
            // Verify sender is a manager
            if (!isManager(senderId)) {
                Map<String, String> response = new HashMap<>();
                response.put("error", "Only managers can send urgent meeting notifications");
                System.out.println("Authorization failed: User is not a manager or not verified/approved");
                return ResponseEntity.status(HttpStatus.FORBIDDEN).body(response);
            }
            
            // Get managers and supervisors as recipients
            List<String> recipients = notificationService.getManagerAndSupervisorIds();
            System.out.println("Found " + recipients.size() + " recipients for urgent meeting notification");
            
            // Create and save the notification
            Notification notification = notificationService.createNotification(
                    request.getTitle(),
                    request.getMessage(),
                    "URGENT_MEETING",
                    senderId,
                    recipients
            );
            
            System.out.println("Successfully created urgent meeting notification with ID: " + notification.getId());
            return ResponseEntity.status(HttpStatus.CREATED).body(notification);
        } catch (Exception e) {
            System.out.println("Error in sendUrgentMeetingNotification: " + e.getMessage());
            e.printStackTrace();
            Map<String, String> response = new HashMap<>();
            response.put("error", "Failed to send urgent meeting notification: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(response);
        }
    }
    
    // Helper methods
    private boolean isSupervisor(String userId) {
        return isUserRole(userId, Role.SUPERVISOR.name());
    }
    
    private boolean isManager(String userId) {
        System.out.println("Checking if user " + userId + " is a manager");
        User user = userRepository.findById(userId).orElse(null);
        if (user == null) {
            System.out.println("User not found with ID: " + userId);
            return false;
        }
        System.out.println("User found - Role: " + user.getRole() + ", Verified: " + user.isVerified() + ", Approved: " + user.isApproved());
        boolean isManager = user.getRole().equals(Role.MANAGER.name());
        boolean isVerified = user.isVerified();
        boolean isApproved = user.isApproved();
        System.out.println("Role check: " + isManager + ", Verified: " + isVerified + ", Approved: " + isApproved);
        return isManager && isVerified && isApproved;
    }
    
    private boolean isUserRole(String userId, String role) {
        User user = userRepository.findById(userId).orElse(null);
        return user != null && user.getRole().equals(role) && user.isVerified() && user.isApproved();
    }
} 