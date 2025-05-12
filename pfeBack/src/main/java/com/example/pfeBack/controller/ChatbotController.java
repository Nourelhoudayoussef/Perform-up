package com.example.pfeBack.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/api/chatbot")
public class ChatbotController {
    
    private final String chatbotUrl = "http://localhost:5001/chatbot";
    
    @Autowired
    private RestTemplate restTemplate;
    
    @PostMapping
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<Map<String, Object>> processChatbotQuery(@RequestBody Map<String, String> request) {
        try {
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
} 