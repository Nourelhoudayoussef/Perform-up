package com.example.pfeBack.service;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import com.example.pfeBack.model.Notification;
import com.example.pfeBack.model.User;
import com.example.pfeBack.model.Role;
import com.example.pfeBack.repository.NotificationRepository;
import com.example.pfeBack.repository.UserRepository;

@Service
public class NotificationService {
    
    @Autowired
    private NotificationRepository notificationRepository;
    
    @Autowired
    private UserRepository userRepository;
    
    public Notification createNotification(String title, String message, String type, String senderId, List<String> recipientIds) {
        Notification notification = new Notification(title, message, type, senderId, recipientIds);
        return notificationRepository.save(notification);
    }
    
    public List<Notification> getNotificationsForUser(String userId) {
        return notificationRepository.findByRecipientIdsContainingOrderByCreatedAtDesc(userId);
    }
    
    public List<Notification> getUnreadNotificationsForUser(String userId) {
        return notificationRepository.findByRecipientIdsContainingAndIsReadFalse(userId);
    }
    
    public List<Notification> getSentNotifications(String senderId) {
        return notificationRepository.findBySenderIdOrderByCreatedAtDesc(senderId);
    }
    
    public Notification markAsRead(String notificationId) {
        Notification notification = notificationRepository.findById(notificationId)
            .orElseThrow(() -> new RuntimeException("Notification not found"));
        notification.setRead(true);
        return notificationRepository.save(notification);
    }
    
    public void deleteNotification(String notificationId) {
        notificationRepository.deleteById(notificationId);
    }
    
    public void deleteNotificationsForUser(String userId) {
        notificationRepository.deleteByRecipientIdsContaining(userId);
    }
    
    public List<String> getTechnicianIds() {
        return userRepository.findByRole(Role.TECHNICIAN.name())
                .stream()
                .filter(user -> user.isVerified() && user.isApproved())
                .map(User::getId)
                .collect(Collectors.toList());
    }
    
    public List<String> getManagerIds() {
        return userRepository.findByRole(Role.MANAGER.name())
                .stream()
                .filter(user -> user.isVerified() && user.isApproved())
                .map(User::getId)
                .collect(Collectors.toList());
    }
    
    public List<String> getSupervisorIds() {
        return userRepository.findByRole(Role.SUPERVISOR.name())
                .stream()
                .filter(user -> user.isVerified() && user.isApproved())
                .map(User::getId)
                .collect(Collectors.toList());
    }
    
    public List<String> getAllUserIds() {
        return userRepository.findAll()
                .stream()
                .filter(user -> user.isVerified() && user.isApproved())
                .map(User::getId)
                .collect(Collectors.toList());
    }
    
    public List<String> getManagerAndSupervisorIds() {
        List<String> recipients = new ArrayList<>();
        recipients.addAll(getManagerIds());
        recipients.addAll(getSupervisorIds());
        return recipients;
    }
    
    public boolean isUserAuthorized(String userId, String requiredRole) {
        Optional<User> userOpt = userRepository.findById(userId);
        if (userOpt.isPresent()) {
            User user = userOpt.get();
            return user.getRole().equals(requiredRole);
        }
        return false;
    }
    
    public boolean isUserAuthorizedToSendNotification(String userId, String type) {
        return userRepository.findById(userId)
            .map(user -> {
                String role = user.getRole();
                return switch (type) {
                    case "URGENT_MEETING", "EMERGENCY" -> role.equals("MANAGER");
                    case "MACHINE_FAILURE", "PRODUCTION_DELAY", "EFFICIENCY_DROP" -> 
                        role.equals("MANAGER") || role.equals("SUPERVISOR");
                    default -> false;
                };
            })
            .orElse(false);
    }
}