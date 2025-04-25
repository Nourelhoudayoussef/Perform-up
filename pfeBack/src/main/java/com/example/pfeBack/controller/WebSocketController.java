package com.example.pfeBack.controller;

import com.example.pfeBack.dto.PerformanceDTO;
import com.example.pfeBack.dto.MachineFailureDTO;
import com.example.pfeBack.model.Performance;
import com.example.pfeBack.model.MachineFailure;
import com.example.pfeBack.model.Notification;
import com.example.pfeBack.repository.PerformanceRepository;
import com.example.pfeBack.repository.MachineFailureRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.SendTo;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;
import org.springframework.stereotype.Service;

import java.util.List;

@Service // Changed to Service for better component classification
public class WebSocketController {

    @Autowired
    private PerformanceRepository performanceRepository;
    
    @Autowired
    private MachineFailureRepository machineFailureRepository;
    
    @Autowired
    private SimpMessagingTemplate messagingTemplate;
    
    /**
     * Broadcast performance update to all subscribed clients
     * @param performance The performance data to broadcast
     */
    public void broadcastPerformanceUpdate(Performance performance) {
        messagingTemplate.convertAndSend(
            "/topic/performance/" + performance.getDate(), 
            performance
        );
    }
    
    /**
     * Broadcast intervention update to all subscribed clients
     * @param intervention The intervention data to broadcast
     */
    public void broadcastInterventionUpdate(MachineFailure intervention) {
        messagingTemplate.convertAndSend(
            "/topic/interventions/" + intervention.getTechnician_id(), 
            intervention
        );
    }
    
    /**
     * Broadcast daily target update to all subscribed clients
     * @param date The date for which the target was updated
     * @param data The target data
     */
    public void broadcastTargetUpdate(String date, Object data) {
        messagingTemplate.convertAndSend("/topic/targets/" + date, data);
    }
    
    /**
     * Broadcast notification to specific recipients in real-time
     * @param notification The notification to broadcast
     */
    public void broadcastNotification(Notification notification) {
        // Send to individual topic for each recipient
        for (String recipientId : notification.getRecipientIds()) {
            messagingTemplate.convertAndSend(
                "/topic/notifications/" + recipientId, 
                notification
            );
        }
        
        // Also send to a global topic based on type
        if (notification.getType() != null) {
            messagingTemplate.convertAndSend(
                "/topic/notifications/type/" + notification.getType().toLowerCase(), 
                notification
            );
        }
    }
} 