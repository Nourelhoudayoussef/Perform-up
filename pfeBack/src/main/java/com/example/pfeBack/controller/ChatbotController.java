package com.example.pfeBack.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;
import org.springframework.security.core.userdetails.UserDetails;
// Import your user repository and entity
import com.example.pfeBack.repository.UserRepository;
import com.example.pfeBack.model.User;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

@RestController
@RequestMapping("/api/chatbot")
public class ChatbotController {
    
    private final String chatbotUrl = "http://localhost:5001/chatbot";
    
    @Autowired
    private RestTemplate restTemplate;
    
    @Autowired
    private UserRepository userRepository;
    
    @PostMapping
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<Map<String, Object>> processChatbotQuery(@RequestBody Map<String, String> request) {
        try {
            // Get the current authenticated user
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            String username = authentication.getName();
            
            // Get the user ID from the username
            Optional<User> userOpt = userRepository.findByUsername(username);
            String userId = userOpt.isPresent() ? userOpt.get().getId() : username;
            
            // Add the user ID to the request if not already present
            if (!request.containsKey("user_id")) {
                request.put("user_id", userId);
            }
            
            // Forward the request to the Flask chatbot service
            ResponseEntity<Map> response = restTemplate.postForEntity(chatbotUrl, request, Map.class);
            return new ResponseEntity<>(response.getBody(), response.getStatusCode());
        } catch (Exception e) {
            Map<String, Object> errorResponse = new HashMap<>();
            errorResponse.put("response", "Failed to communicate with chatbot service: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(errorResponse);
        }
    }
    
    @GetMapping("/diagnostics")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<Object> getChatbotDiagnostics() {
        try {
            // Forward the request to the Flask chatbot diagnostics endpoint
            ResponseEntity<Object> response = restTemplate.getForEntity(
                    "http://localhost:5001/chatbot/diagnostics", Object.class);
            return new ResponseEntity<>(response.getBody(), response.getStatusCode());
        } catch (Exception e) {
            Map<String, String> errorResponse = new HashMap<>();
            errorResponse.put("error", "Failed to get chatbot diagnostics: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(errorResponse);
        }
    }
    
    @GetMapping("/history")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<Object> getChatbotHistory() {
        try {
            // Get the current authenticated user
            Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
            String username = authentication.getName();
            
            // Get the user ID from the username
            Optional<User> userOpt = userRepository.findByUsername(username);
            String userId = userOpt.isPresent() ? userOpt.get().getId() : username;
            
            // Forward the request to the Flask chatbot history endpoint
            ResponseEntity<Object> response = restTemplate.getForEntity(
                    "http://localhost:5001/chatbot/history/" + userId, Object.class);
            return new ResponseEntity<>(response.getBody(), response.getStatusCode());
        } catch (Exception e) {
            Map<String, String> errorResponse = new HashMap<>();
            errorResponse.put("error", "Failed to get conversation history: " + e.getMessage());
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).body(errorResponse);
        }
    }
} 