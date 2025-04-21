package com.example.pfeBack.model;

import java.time.LocalDateTime;
import java.util.List;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "notifications")
public class Notification {
    
    @Id
    private String id;
    private String title;
    private String message;
    private String type; // MACHINE_FAILURE, PRODUCTION_DELAY, EFFICIENCY_DROP, EMERGENCY, URGENT_MEETING
    private String senderId;
    private List<String> recipientIds; // IDs of users who should receive this notification
    private boolean isRead;
    private LocalDateTime createdAt;
    
    public Notification() {
        this.isRead = false;
        this.createdAt = LocalDateTime.now();
    }
    
    public Notification(String title, String message, String type, String senderId, List<String> recipientIds) {
        this.title = title;
        this.message = message;
        this.type = type;
        this.senderId = senderId;
        this.recipientIds = recipientIds;
        this.isRead = false;
        this.createdAt = LocalDateTime.now();
    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public String getTitle() {
        return title;
    }

    public void setTitle(String title) {
        this.title = title;
    }

    public String getMessage() {
        return message;
    }

    public void setMessage(String message) {
        this.message = message;
    }

    public String getType() {
        return type;
    }

    public void setType(String type) {
        this.type = type;
    }

    public String getSenderId() {
        return senderId;
    }

    public void setSenderId(String senderId) {
        this.senderId = senderId;
    }

    public List<String> getRecipientIds() {
        return recipientIds;
    }

    public void setRecipientIds(List<String> recipientIds) {
        this.recipientIds = recipientIds;
    }

    public boolean isRead() {
        return isRead;
    }

    public void setRead(boolean isRead) {
        this.isRead = isRead;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }
} 