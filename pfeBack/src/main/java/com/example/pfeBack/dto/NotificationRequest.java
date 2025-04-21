package com.example.pfeBack.dto;

public class NotificationRequest {
    private String title;
    private String message;
    private String senderId;
    
    public NotificationRequest() {
    }
    
    public NotificationRequest(String title, String message, String senderId) {
        this.title = title;
        this.message = message;
        this.senderId = senderId;
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

    public String getSenderId() {
        return senderId;
    }

    public void setSenderId(String senderId) {
        this.senderId = senderId;
    }
} 