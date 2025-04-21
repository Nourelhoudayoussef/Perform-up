package com.example.pfeBack.controller;

import com.example.pfeBack.model.User;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import com.example.pfeBack.repository.UserRepository;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/admin")
@CrossOrigin(origins = "*")
public class AdminController {

    private static final Logger logger = LoggerFactory.getLogger(AdminController.class);

    @Autowired
    private UserRepository userRepository;

    /**
     * Get all users pending approval
     * @return List of users pending approval
     */
    @GetMapping("/pending-users")
    public ResponseEntity<?> getPendingUsers() {
        logger.info("Getting list of users pending approval");
        
        try {
            List<Map<String, Object>> pendingUsers = userRepository.findByVerifiedTrueAndApprovedFalse()
                .stream()
                .map(user -> {
                    Map<String, Object> userMap = new HashMap<>();
                    userMap.put("id", user.getId());
                    userMap.put("email", user.getEmail());
                    userMap.put("username", user.getUsername());
                    userMap.put("role", user.getRole());
                    return userMap;
                })
                .collect(Collectors.toList());
            
            logger.info("Found {} users pending approval", pendingUsers.size());
            return ResponseEntity.ok(pendingUsers);
        } catch (Exception e) {
            logger.error("Error getting pending users: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("Error getting pending users: " + e.getMessage());
        }
    }

    /**
     * Get all users for the manage users screen
     * @return List of all users with their status
     */
    @GetMapping("/all-users")
    public ResponseEntity<?> getAllUsers() {
        logger.info("Getting list of all users for manage users screen");
        
        try {
            List<Map<String, Object>> allUsers = userRepository.findAll()
                .stream()
                .map(user -> {
                    Map<String, Object> userMap = new HashMap<>();
                    userMap.put("id", user.getId());
                    userMap.put("email", user.getEmail());
                    userMap.put("username", user.getUsername());
                    userMap.put("role", user.getRole());
                    userMap.put("verified", user.isVerified());
                    userMap.put("approved", user.isApproved());
                    userMap.put("status", determineUserStatus(user));
                    return userMap;
                })
                .collect(Collectors.toList());
            
            logger.info("Found {} users in total", allUsers.size());
            return ResponseEntity.ok(allUsers);
        } catch (Exception e) {
            logger.error("Error getting all users: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("Error getting all users: " + e.getMessage());
        }
    }

    /**
     * Helper method to determine user status
     * @param user The user to check
     * @return Status string
     */
    private String determineUserStatus(User user) {
        if (!user.isVerified()) {
            return "Unverified";
        } else if (!user.isApproved()) {
            return "Pending Approval";
        } else {
            return "Active";
        }
    }

    /**
     * Approve a user by ID
     * @param userId User ID to approve
     * @return Success or error message
     */
    @PostMapping("/approve-user/{userId}")
    public ResponseEntity<?> approveUser(@PathVariable String userId) {
        logger.info("Approving user with ID: {}", userId);
        
        try {
            Optional<User> userOptional = userRepository.findById(userId);
            if (!userOptional.isPresent()) {
                logger.error("User not found with ID: {}", userId);
                return ResponseEntity.status(HttpStatus.NOT_FOUND).body("User not found");
            }
            
            User user = userOptional.get();
            
            // Check if user is already approved
            if (user.isApproved()) {
                logger.info("User is already approved: {}", userId);
                return ResponseEntity.ok("User is already approved");
            }
            
            // Approve the user
            user.setApproved(true);
            userRepository.save(user);
            
            logger.info("User approved successfully: {}", userId);
            return ResponseEntity.ok("User approved successfully");
        } catch (Exception e) {
            logger.error("Error approving user: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("Error approving user: " + e.getMessage());
        }
    }

    /**
     * Simple test endpoint to check if AdminController is working
     * @return A simple message
     */
    @GetMapping("/test")
    public ResponseEntity<String> testEndpoint() {
        logger.info("Admin test endpoint called");
        return ResponseEntity.ok("Admin controller is working!");
    }
}