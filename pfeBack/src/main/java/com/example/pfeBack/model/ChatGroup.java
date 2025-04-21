package com.example.pfeBack.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Document(collection = "conversations")
public class ChatGroup {
    @Id
    private String id;
    private List<String> participants; // Renamed from memberIds to match the collection
    private LocalDateTime createdAt;
    private LocalDateTime lastActivity; // Equivalent to lastMessageTime
    private String title; // Equivalent to name
    private boolean isGroupChat; // New field to match the collection
    private String _class; // New field to match the collection
    private String lastMessage;
    private Map<String, LocalDateTime> lastReadTimestamps = new HashMap<>();

    public ChatGroup() {
        this.participants = new ArrayList<>();
        this.createdAt = LocalDateTime.now();
        this.lastActivity = LocalDateTime.now();
        this.lastReadTimestamps = new HashMap<>();
        this._class = "com.example.pfeBack.model.ChatGroup";
    }

    public ChatGroup(String title, String creatorId) {
        this.title = title;
        this.participants = new ArrayList<>();
        this.participants.add(creatorId);
        this.createdAt = LocalDateTime.now();
        this.lastActivity = LocalDateTime.now();
        this.lastReadTimestamps = new HashMap<>();
        this.isGroupChat = false; // Default to false, will be set based on number of participants
        this._class = "com.example.pfeBack.model.ChatGroup";
    }

    // Getters and Setters
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

    // For backward compatibility
    public String getName() {
        return title;
    }

    public void setName(String name) {
        this.title = name;
    }

    public String getCreatorId() {
        return participants.isEmpty() ? null : participants.get(0);
    }

    public void setCreatorId(String creatorId) {
        if (participants.isEmpty()) {
            participants.add(creatorId);
        } else {
            participants.set(0, creatorId);
        }
    }

    public List<String> getParticipants() {
        return participants;
    }

    public void setParticipants(List<String> participants) {
        this.participants = participants;
        // Update isGroupChat based on number of participants
        this.isGroupChat = participants.size() > 2;
    }

    // For backward compatibility
    public List<String> getMemberIds() {
        return participants;
    }

    public void setMemberIds(List<String> memberIds) {
        this.participants = memberIds;
        // Update isGroupChat based on number of participants
        this.isGroupChat = memberIds.size() > 2;
    }

    public LocalDateTime getCreatedAt() {
        return createdAt;
    }

    public void setCreatedAt(LocalDateTime createdAt) {
        this.createdAt = createdAt;
    }

    public LocalDateTime getLastActivity() {
        return lastActivity;
    }

    public void setLastActivity(LocalDateTime lastActivity) {
        this.lastActivity = lastActivity;
    }

    // For backward compatibility
    public LocalDateTime getLastMessageTime() {
        return lastActivity;
    }

    public void setLastMessageTime(LocalDateTime lastMessageTime) {
        this.lastActivity = lastMessageTime;
    }

    public String getLastMessage() {
        return lastMessage;
    }

    public void setLastMessage(String lastMessage) {
        this.lastMessage = lastMessage;
    }
    
    public Map<String, LocalDateTime> getLastReadTimestamps() {
        return lastReadTimestamps;
    }

    public void setLastReadTimestamps(Map<String, LocalDateTime> lastReadTimestamps) {
        this.lastReadTimestamps = lastReadTimestamps;
    }
    
    public boolean isGroupChat() {
        return isGroupChat;
    }
    
    public void setGroupChat(boolean groupChat) {
        isGroupChat = groupChat;
    }
    
    public String get_class() {
        return _class;
    }
    
    public void set_class(String _class) {
        this._class = _class;
    }

    // Helper methods
    public void addParticipant(String userId) {
        if (!participants.contains(userId)) {
            participants.add(userId);
            // Update isGroupChat based on number of participants
            this.isGroupChat = participants.size() > 2;
        }
    }

    public void removeParticipant(String userId) {
        participants.remove(userId);
        // Update isGroupChat based on number of participants
        this.isGroupChat = participants.size() > 2;
    }

    public void updateLastMessage(String content) {
        this.lastMessage = content;
        this.lastActivity = LocalDateTime.now();
    }
}