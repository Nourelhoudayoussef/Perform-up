package com.example.pfeBack.controller;

import com.example.pfeBack.model.ChatGroup;
import com.example.pfeBack.model.Message;
import com.example.pfeBack.model.User;
import com.example.pfeBack.repository.ChatGroupRepository;
import com.example.pfeBack.repository.MessageRepository;
import com.example.pfeBack.repository.UserRepository;
import com.example.pfeBack.service.ChatService;
import lombok.Data;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;
import java.util.stream.Stream;

@RestController
@RequestMapping("/chat")
public class ChatController {

    @Autowired
    private ChatGroupRepository chatGroupRepository;

    @Autowired
    private MessageRepository messageRepository;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private SimpMessagingTemplate messagingTemplate;

    private final ChatService chatService;

    public ChatController(ChatService chatService) {
        this.chatService = chatService;
    }

    @PostMapping("/groups")
    public ResponseEntity<?> createChatGroup(@RequestBody Map<String, Object> request) {
        try {
            String title = (String) request.get("title");
            String creatorId = (String) request.get("creatorId");
            @SuppressWarnings("unchecked")
			List<String> participants = (List<String>) request.get("participants");

            if (title == null || creatorId == null || participants == null) {
                return ResponseEntity.badRequest().body(Map.of("message", "Missing required parameters"));
            }

            ChatGroup chatGroup = new ChatGroup(title, creatorId);
            for (String participant : participants) {
                chatGroup.addParticipant(participant);
            }

            chatGroup = chatGroupRepository.save(chatGroup);
            return ResponseEntity.ok(chatGroup);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error creating chat group: " + e.getMessage()));
        }
    }

    @GetMapping("/groups/user/{userId}")
    public ResponseEntity<?> getUserChatGroups(@PathVariable String userId) {
        try {
            List<ChatGroup> groups = chatGroupRepository.findByParticipantsContaining(userId);
            return ResponseEntity.ok(groups);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error fetching chat groups: " + e.getMessage()));
        }
    }

    @GetMapping("/groups/search")
    public ResponseEntity<?> searchChatGroupsByName(@RequestParam String title) {
        try {
            List<ChatGroup> groups = chatGroupRepository.findByTitleContainingIgnoreCase(title);
            return ResponseEntity.ok(groups);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error searching chat groups: " + e.getMessage()));
        }
    }

    @GetMapping("/groups/{groupId}")
    public ResponseEntity<?> getChatGroupDetails(@PathVariable String groupId) {
        try {
            Optional<ChatGroup> groupOpt = chatGroupRepository.findById(groupId);
            if (groupOpt.isEmpty()) {
                return ResponseEntity.notFound().build();
            }

            ChatGroup group = groupOpt.get();
            List<Map<String, Object>> members = ((Stream<Map<String, Object>>) userRepository.findAllById(group.getParticipants())
                    .stream()
                    .map(user -> {
                        Map<String, Object> userMap = new HashMap<>();
                        userMap.put("id", user.getId());
                        userMap.put("username", user.getUsername());
                        return userMap;
                    }))
                    .toList();

            Map<String, Object> response = new HashMap<>();
            response.put("group", group);
            response.put("members", members);

            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error fetching group details: " + e.getMessage()));
        }
    }

    @PostMapping("/messages")
    public ResponseEntity<?> sendMessage(@RequestBody Map<String, Object> request) {
        try {
            String senderId = (String) request.get("senderId");
            String chatGroupId = (String) request.get("chatGroupId");
            String content = (String) request.get("content");

            if (senderId == null || chatGroupId == null || content == null) {
                return ResponseEntity.badRequest().body(Map.of("message", "Missing required parameters"));
            }

            System.out.println("Sending message from: " + senderId + " to chat: " + chatGroupId);

            String senderName = userRepository.findById(senderId)
                    .map(user -> user.getUsername())
                    .orElse("Unknown User");

            Message message = new Message(senderId, chatGroupId, content, senderName);
            message = messageRepository.save(message);

            // Update last message in chat group and mark as read for sender only
            chatGroupRepository.findById(chatGroupId).ifPresent(group -> {
                group.updateLastMessage(content);
                // Debug: Print the lastReadTimestamps before update
                System.out.println("Before update - lastReadTimestamps: " + group.getLastReadTimestamps());
                // Get current time to use for all timestamp updates
                LocalDateTime now = LocalDateTime.now();
                // Mark as read for the sender only
                group.getLastReadTimestamps().put(senderId, now);
                // Update the last activity timestamp for the group
                group.setLastActivity(now);
                // Debug: Print the lastReadTimestamps after update
                System.out.println("After update - lastReadTimestamps: " + group.getLastReadTimestamps());
                chatGroupRepository.save(group);
            });

            System.out.println("[ChatController] Broadcasting to /topic/chat/" + chatGroupId + " | senderId: " + senderId + ", content: " + content);
            // Broadcast the message to WebSocket subscribers
            messagingTemplate.convertAndSend("/topic/chat/" + chatGroupId, message);

            return ResponseEntity.ok(message);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error sending message: " + e.getMessage()));
        }
    }

    @GetMapping("/messages/{groupId}")
    public ResponseEntity<?> getGroupMessages(
            @PathVariable String groupId,
            @RequestParam(required = false) String timestamp) {
        try {
            List<Message> messages;
            if (timestamp != null) {
                LocalDateTime since = LocalDateTime.parse(timestamp);
                messages = messageRepository.findByChatGroupIdAndTimestampAfterOrderByTimestampAsc(groupId, since);
            } else {
                messages = messageRepository.findByChatGroupIdOrderByTimestampAsc(groupId);
            }
            return ResponseEntity.ok(messages);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error fetching messages: " + e.getMessage()));
        }
    }

    @PostMapping("/groups/{groupId}/participants")
    public ResponseEntity<?> addGroupParticipant(
            @PathVariable String groupId,
            @RequestBody Map<String, Object> request) {
        try {
            Object userIdObj = request.get("userId");
            if (userIdObj == null) {
                return ResponseEntity.badRequest().body(Map.of("message", "Missing userId parameter"));
            }
            
            // Convert userId to String regardless of original type
            String userId = userIdObj.toString();
            
            System.out.println("Adding participant with userId: " + userId + " to group: " + groupId);
            System.out.println("Request body: " + request);

            Optional<ChatGroup> groupOpt = chatGroupRepository.findById(groupId);
            if (groupOpt.isEmpty()) {
                return ResponseEntity.notFound().build();
            }

            ChatGroup group = groupOpt.get();
            group.addParticipant(userId);
            chatGroupRepository.save(group);

            return ResponseEntity.ok(Map.of("message", "Participant added successfully"));
        } catch (Exception e) {
            e.printStackTrace(); // Print stack trace for debugging
            return ResponseEntity.badRequest().body(Map.of("message", "Error adding participant: " + e.getMessage()));
        }
    }

    @DeleteMapping("/groups/{groupId}/participants/{userId}")
    public ResponseEntity<?> removeGroupParticipant(
            @PathVariable String groupId,
            @PathVariable String userId) {
        try {
            Optional<ChatGroup> groupOpt = chatGroupRepository.findById(groupId);
            if (groupOpt.isEmpty()) {
                return ResponseEntity.notFound().build();
            }

            ChatGroup group = groupOpt.get();
            group.removeParticipant(userId);
            chatGroupRepository.save(group);

            return ResponseEntity.ok(Map.of("message", "Participant removed successfully"));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error removing participant: " + e.getMessage()));
        }
    }

    @PostMapping("/messages/individual")
    public ResponseEntity<?> sendIndividualMessage(@RequestBody Map<String, Object> request) {
        try {
            String senderId = (String) request.get("senderId");
            String receiverId = (String) request.get("receiverId");
            String content = (String) request.get("content");

            if (senderId == null || receiverId == null || content == null) {
                return ResponseEntity.badRequest().body(Map.of("message", "Missing required parameters"));
            }

            // Get sender's username
            String senderName = userRepository.findById(senderId)
                    .map(user -> user.getUsername())
                    .orElse("Unknown User");

            // Create a unique chat group ID for these two users
            String chatGroupId = generateIndividualChatId(senderId, receiverId);

            // Create or get the chat group
            ChatGroup chatGroup = chatGroupRepository.findById(chatGroupId)
                    .orElseGet(() -> {
                        ChatGroup newGroup = new ChatGroup("Individual Chat", senderId);
                        newGroup.setId(chatGroupId); // Set the ID explicitly
                        newGroup.addParticipant(senderId);
                        newGroup.addParticipant(receiverId);
                        return chatGroupRepository.save(newGroup);
                    });

            // Create and save the message
            Message message = new Message(senderId, chatGroupId, content, senderName);
            message.setReceiverId(receiverId); // Ensure receiverId is set
            message = messageRepository.save(message);

            // Update last message in chat group and mark as read for sender only
            chatGroup.updateLastMessage(content);
            // Debug: Print the lastReadTimestamps before update
            System.out.println("Before update - lastReadTimestamps: " + chatGroup.getLastReadTimestamps());
            // Mark as read for the sender only
            chatGroup.getLastReadTimestamps().put(senderId, LocalDateTime.now());
            // Debug: Print the lastReadTimestamps after update
            System.out.println("After update - lastReadTimestamps: " + chatGroup.getLastReadTimestamps());
            chatGroupRepository.save(chatGroup);

            System.out.println("[ChatController] Broadcasting to /topic/chat/" + chatGroupId + " | senderId: " + senderId + ", receiverId: " + receiverId + ", content: " + content);
            // Broadcast the message to WebSocket subscribers
            messagingTemplate.convertAndSend("/topic/chat/" + chatGroupId, message);

            return ResponseEntity.ok(message);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error sending message: " + e.getMessage()));
        }
    }

    @GetMapping("/messages/individual/{userId1}/{userId2}")
    public ResponseEntity<?> getIndividualMessages(
            @PathVariable String userId1,
            @PathVariable String userId2) {
        try {
            String chatGroupId = generateIndividualChatId(userId1, userId2);
            List<Message> messages = messageRepository.findByChatGroupIdOrderByTimestampAsc(chatGroupId);
            return ResponseEntity.ok(messages);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error fetching messages: " + e.getMessage()));
        }
    }

    private String generateIndividualChatId(String userId1, String userId2) {
        // Sort the IDs to ensure consistent chat group ID regardless of order
        String[] ids = {userId1, userId2};
        java.util.Arrays.sort(ids);
        return "individual_" + ids[0] + "_" + ids[1];
    }

    @GetMapping("/search-users")
    public ResponseEntity<?> searchUsers(@RequestParam(required = false) String username) {
        try {
            List<User> users;
            if (username != null && !username.isEmpty()) {
                users = userRepository.findByUsernameContainingIgnoreCaseAndVerifiedTrueAndApprovedTrue(username);
            } else {
                users = userRepository.findByVerifiedTrueAndApprovedTrue();
            }
            
            // Transform the result to only include necessary user information
            List<Map<String, Object>> usersList = users.stream()
                .map(user -> {
                    Map<String, Object> userMap = new HashMap<>();
                    userMap.put("id", user.getId());
                    userMap.put("username", user.getUsername());
                    userMap.put("email", user.getEmail());
                    userMap.put("role", user.getRole());
                    return userMap;
                })
                .collect(Collectors.toList());
                
            return ResponseEntity.ok(usersList);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error searching users: " + e.getMessage()));
        }
    }
    
    @GetMapping("/groups/{groupId}/available-users")
    public ResponseEntity<?> getAvailableUsers(@PathVariable String groupId) {
        try {
            Optional<ChatGroup> groupOpt = chatGroupRepository.findById(groupId);
            if (groupOpt.isEmpty()) {
                return ResponseEntity.notFound().build();
            }
            
            ChatGroup group = groupOpt.get();
            List<String> participants = group.getParticipants();
            
            // Find users who are not already members of the group
            List<User> availableUsers = userRepository.findByIdNotInAndVerifiedTrueAndApprovedTrue(participants);
            
            // Transform the result to only include necessary user information
            List<Map<String, Object>> usersList = availableUsers.stream()
                .map(user -> {
                    Map<String, Object> userMap = new HashMap<>();
                    userMap.put("id", user.getId());
                    userMap.put("username", user.getUsername());
                    userMap.put("email", user.getEmail());
                    userMap.put("role", user.getRole());
                    return userMap;
                })
                .collect(Collectors.toList());
                
            return ResponseEntity.ok(usersList);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error getting available users: " + e.getMessage()));
        }
    }
    
    @GetMapping("/groups/{groupId}/search-users")
    public ResponseEntity<?> searchAvailableUsers(
            @PathVariable String groupId,
            @RequestParam String username) {
        try {
            Optional<ChatGroup> groupOpt = chatGroupRepository.findById(groupId);
            if (groupOpt.isEmpty()) {
                return ResponseEntity.notFound().build();
            }
            
            ChatGroup group = groupOpt.get();
            List<String> participants = group.getParticipants();
            
            // Find all eligible users
            List<User> allUsers = userRepository.findByUsernameContainingIgnoreCaseAndVerifiedTrueAndApprovedTrue(username);
            
            // Filter out users who are already members
            List<Map<String, Object>> availableUsers = allUsers.stream()
                .filter(user -> !participants.contains(user.getId()))
                .map(user -> {
                    Map<String, Object> userMap = new HashMap<>();
                    userMap.put("id", user.getId());
                    userMap.put("username", user.getUsername());
                    userMap.put("email", user.getEmail());
                    userMap.put("role", user.getRole());
                    return userMap;
                })
                .collect(Collectors.toList());
                
            return ResponseEntity.ok(availableUsers);
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error searching available users: " + e.getMessage()));
        }
    }

    @DeleteMapping("/groups/{groupId}")
    public ResponseEntity<?> deleteChatGroup(@PathVariable String groupId) {
        try {
            Optional<ChatGroup> groupOpt = chatGroupRepository.findById(groupId);
            if (groupOpt.isEmpty()) {
                return ResponseEntity.notFound().build();
            }
            
            // Delete all messages in the group
            List<Message> messages = messageRepository.findByChatGroupIdOrderByTimestampAsc(groupId);
            messageRepository.deleteAll(messages);
            
            // Delete the group
            chatGroupRepository.deleteById(groupId);
            
            return ResponseEntity.ok(Map.of("message", "Chat group deleted successfully"));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of("message", "Error deleting chat group: " + e.getMessage()));
        }
    }

    @PostMapping("/create-group")
    public ResponseEntity<?> createGroup(@RequestBody Map<String, Object> request) {
        try {
            String groupName = (String) request.get("groupName");
            @SuppressWarnings("unchecked")
            List<String> participants = (List<String>) request.get("participants");
            
            if (groupName == null || participants == null || participants.isEmpty()) {
                return ResponseEntity.badRequest().body("Group name and participant IDs are required");
            }

            ChatGroup group = chatGroupRepository.save(new ChatGroup(groupName, participants.get(0)));
            for (String participant : participants) {
                group.addParticipant(participant);
            }

            Map<String, Object> response = new HashMap<>();
            response.put("groupId", group.getId());
            response.put("groupName", group.getTitle());
            response.put("participants", group.getParticipants().stream()
                .map(participantId -> {
                    Map<String, Object> participantInfo = new HashMap<>();
                    participantInfo.put("id", participantId);
                    // Get username from user repository
                    userRepository.findById(participantId).ifPresent(user -> 
                        participantInfo.put("username", user.getUsername())
                    );
                    return participantInfo;
                })
                .collect(Collectors.toList()));
            
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("Error creating group: " + e.getMessage());
        }
    }

    /**
     * Mark a chat as read for a specific user
     * @param chatId The ID of the chat group
     * @param userId The ID of the user marking the chat as read
     * @return Success response or error
     */
    @PostMapping("/chats/{chatId}/read")
    public ResponseEntity<?> markChatAsRead(@PathVariable String chatId, @RequestParam String userId) {
        try {
            ChatGroup group;
            Optional<ChatGroup> groupOpt = chatGroupRepository.findById(chatId);
            
            if (groupOpt.isEmpty()) {
                // For individual chats, the chat might not exist yet if no messages have been sent
                if (chatId.startsWith("individual_")) {
                    // Extract user IDs from the chatId
                    String[] parts = chatId.split("_");
                    if (parts.length == 3) {
                        String userId1 = parts[1];
                        String userId2 = parts[2];
                        
                        // Create a new chat group for these users
                        group = new ChatGroup("Individual Chat", userId1);
                        group.setId(chatId);
                        group.addParticipant(userId1);
                        group.addParticipant(userId2);
                        group = chatGroupRepository.save(group);
                        System.out.println("Created new chat group for marking as read: " + chatId);
                    } else {
                        return ResponseEntity.notFound().build();
                    }
                } else {
                    return ResponseEntity.notFound().build();
                }
            } else {
                group = groupOpt.get();
            }
            
            // Check if user is a participant of the group
            if (!group.getParticipants().contains(userId)) {
                return ResponseEntity.status(HttpStatus.FORBIDDEN)
                    .body(Map.of("message", "User is not a participant of this chat"));
            }
            
            // Update the last read timestamp for this user
            group.getLastReadTimestamps().put(userId, LocalDateTime.now());
            chatGroupRepository.save(group);
            
            return ResponseEntity.ok(Map.of("message", "Chat marked as read"));
        } catch (Exception e) {
            e.printStackTrace(); // Add this for better debugging
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("message", "Error marking chat as read: " + e.getMessage()));
        }
    }
    
    /**
     * Get unread message counts for all chats for a user
     * @param userId The ID of the user
     * @return Map of chat IDs to unread message counts
     */
    @GetMapping("/chats/unread-counts")
    public ResponseEntity<?> getUnreadCounts(@RequestParam String userId) {
        try {
            System.out.println("Getting unread counts for user: " + userId);
            
            // Find all groups the user is a participant of
            List<ChatGroup> groups = chatGroupRepository.findByParticipantsContaining(userId);
            System.out.println("Found " + groups.size() + " groups for user");
            
            Map<String, Integer> unreadCounts = new HashMap<>();
            
            // Use a reasonable default date instead of LocalDateTime.MIN
            LocalDateTime defaultDate = LocalDateTime.of(2000, 1, 1, 0, 0);
            
            for (ChatGroup group : groups) {
                // Get the last time the user read this chat
                LocalDateTime lastRead = group.getLastReadTimestamps().getOrDefault(userId, defaultDate);
                System.out.println("Group: " + group.getId() + ", lastRead: " + lastRead);
                
                // Count messages after that timestamp
                int count = messageRepository.countByChatGroupIdAndTimestampAfter(group.getId(), lastRead);
                System.out.println("Group: " + group.getId() + ", unread count: " + count);
                
                unreadCounts.put(group.getId(), count);
            }
            
            // For individual chats, we need to check messages where chatGroupId is constructed from user IDs
            List<User> allUsers = userRepository.findAll();
            System.out.println("Checking individual chats with " + allUsers.size() + " users");
            
            for (User otherUser : allUsers) {
                if (!otherUser.getId().equals(userId)) {
                    String chatId = generateIndividualChatId(userId, otherUser.getId());
                    System.out.println("Checking individual chat: " + chatId + " with user: " + otherUser.getUsername());
                    
                    // Find the last time the user read this individual chat
                    // For individual chats, we need to check if any group exists with this ID
                    Optional<ChatGroup> individualChatOpt = chatGroupRepository.findById(chatId);
                    if (individualChatOpt.isPresent()) {
                        ChatGroup individualChat = individualChatOpt.get();
                        LocalDateTime lastRead = individualChat.getLastReadTimestamps().getOrDefault(userId, defaultDate);
                        System.out.println("Individual chat: " + chatId + ", lastRead: " + lastRead);
                        
                        int count = messageRepository.countByChatGroupIdAndTimestampAfter(chatId, lastRead);
                        System.out.println("Individual chat: " + chatId + ", unread count: " + count);
                        
                        unreadCounts.put(chatId, count);
                    }
                }
            }
            
            System.out.println("Final unread counts: " + unreadCounts);
            return ResponseEntity.ok(unreadCounts);
        } catch (Exception e) {
            System.err.println("Error getting unread counts: " + e.getMessage());
            e.printStackTrace();
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("message", "Error getting unread counts: " + e.getMessage()));
        }
    }

    /**
     * Get the last message for each conversation between the current user and a list of other users
     * This optimizes the chat list loading by fetching all last messages in a single API call
     * 
     * @param currentUserId The ID of the current user
     * @param userIds List of user IDs to get last messages for
     * @return Map of userId to last message content
     */
    @PostMapping("/messages/last-messages")
    public ResponseEntity<Map<String, Map<String, Object>>> getLastMessagesForUsers(@RequestBody Map<String, Object> requestBody) {
        String currentUserId = (String) requestBody.get("currentUserId");
        @SuppressWarnings("unchecked")
        List<String> userIds = (List<String>) requestBody.get("userIds");
        
        Map<String, Map<String, Object>> result = new HashMap<>();
        
        for (String userId : userIds) {
            // Generate chat ID using the same logic as in the frontend
            String chatId = generateIndividualChatId(currentUserId, userId);
            
            // Find the last message in this conversation
            Message lastMessage = messageRepository.findTopByChatGroupIdOrderByTimestampDesc(chatId);
            
            if (lastMessage != null) {
            Map<String, Object> messageInfo = new HashMap<>();
            String content = lastMessage.getContent();
            if (content.length() > 30) {
                content = content.substring(0, 27) + "...";
            }
            messageInfo.put("content", content);
            messageInfo.put("timestamp", lastMessage.getTimestamp()); // Make sure this is serializable (e.g., String or ISO format)
            result.put(userId, messageInfo);
        }
    }

    return ResponseEntity.ok(result);
}

    @PostMapping("/chat")
    public Mono<ResponseEntity<String>> chat(@RequestBody ChatRequest request) {
        return chatService.getChatResponse(request.getQuestion())
                .map(ResponseEntity::ok);
    }

    @Data
    public static class ChatRequest {
        private String question;
    }
}