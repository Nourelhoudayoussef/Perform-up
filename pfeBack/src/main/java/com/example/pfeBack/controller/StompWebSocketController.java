package com.example.pfeBack.controller;

import com.example.pfeBack.model.MachineFailure;
import com.example.pfeBack.model.Performance;
import com.example.pfeBack.model.Notification;
import com.example.pfeBack.repository.MachineFailureRepository;
import com.example.pfeBack.repository.PerformanceRepository;
import com.example.pfeBack.repository.NotificationRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.SendTo;
import org.springframework.stereotype.Controller;

import java.util.ArrayList;
import java.util.List;

/**
 * Controller to handle STOMP WebSocket subscriptions
 */
@Controller
public class StompWebSocketController {
    
    @Autowired
    private PerformanceRepository performanceRepository;
    
    @Autowired
    private MachineFailureRepository machineFailureRepository;
    
    @Autowired
    private NotificationRepository notificationRepository;
    
    /**
     * Handles subscription to performance data for a specific date
     * @param date The date to subscribe to
     * @return List of performance data for the date
     */
    @MessageMapping("/subscribe-performance/{date}")
    @SendTo("/topic/performance/{date}")
    public List<Performance> subscribeToPerformance(@DestinationVariable String date) {
        return performanceRepository.findByDate(date);
    }
    
    /**
     * Handles subscription to intervention data for a specific technician
     * @param technicianId The technician ID to subscribe to
     * @return List of interventions for the technician
     */
    @MessageMapping("/subscribe-interventions/{technicianId}")
    @SendTo("/topic/interventions/{technicianId}")
    public List<MachineFailure> subscribeToInterventions(@DestinationVariable String technicianId) {
        return machineFailureRepository.findByTechnician_id(technicianId);
    }
    
    /**
     * Handles subscription to daily targets for a specific date
     * @param date The date to subscribe to
     * @return List of performances with targets for the date
     */
    @MessageMapping("/subscribe-targets/{date}")
    @SendTo("/topic/targets/{date}")
    public List<Performance> subscribeToTargets(@DestinationVariable String date) {
        return performanceRepository.findByDate(date);
    }
    
    /**
     * Handles subscription to notifications for a specific user
     * @param userId The user ID to subscribe to
     * @return List of unread notifications for the user
     */
    @MessageMapping("/subscribe-notifications/{userId}")
    @SendTo("/topic/notifications/{userId}")
    public List<Notification> subscribeToNotifications(@DestinationVariable String userId) {
        return notificationRepository.findByRecipientIdsContainingAndIsReadFalse(userId);
    }

    /**
     * Handles subscription to notifications of a specific type
     * @param type The notification type to subscribe to
     * @return Empty list initially (will receive notifications as they come)
     */
    @MessageMapping("/subscribe-notifications/type/{type}")
    @SendTo("/topic/notifications/type/{type}")
    public List<Notification> subscribeToNotificationType(@DestinationVariable String type) {
        // Just return an empty list initially
        return new ArrayList<>();
    }
} 