package com.example.pfeBack.controller;

import com.example.pfeBack.dto.AuthRequest;
import com.example.pfeBack.dto.AuthResponse;
import com.example.pfeBack.model.User;
import com.example.pfeBack.repository.UserRepository;
import com.example.pfeBack.service.EmailService;
import com.example.pfeBack.service.JwtUtil;
import com.example.pfeBack.service.UserService;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;
import java.util.Random;

@RestController
@RequestMapping("/auth")
public class AuthenticationController {
    private static final Logger logger = LoggerFactory.getLogger(AuthenticationController.class);

    private final UserService userService;
    private final UserRepository userRepository;
    private final EmailService emailService;
    private final JwtUtil jwtUtil;
    private final PasswordEncoder passwordEncoder;

    public AuthenticationController(UserService userService, 
                                    UserRepository userRepository, 
                                    EmailService emailService, 
                                    AuthenticationManager authenticationManager, 
                                    JwtUtil jwtUtil,
                                    PasswordEncoder passwordEncoder) {
        this.userService = userService;
        this.userRepository = userRepository;
        this.emailService = emailService;
        this.jwtUtil = jwtUtil;
        this.passwordEncoder = passwordEncoder;
    }

    @PostMapping("/register")
    public ResponseEntity<?> register(@RequestBody User user) {
        // Check if email already exists
        if (userRepository.existsByEmail(user.getEmail())) {
            return ResponseEntity.badRequest().body("Email already exists");
        }

        // Check if username already exists
        if (userRepository.existsByUsername(user.getUsername())) {
            return ResponseEntity.badRequest().body("Username already exists");
        }

        userService.register(user);
        return ResponseEntity.ok("Verification code sent to email");
    }

    @PostMapping("/signup")
    public ResponseEntity<?> signup(@RequestBody User user) {
        // Check if email already exists
        if (userRepository.existsByEmail(user.getEmail())) {
            return ResponseEntity.badRequest().body("Email already exists");
        }

        // Check if username already exists
        if (userRepository.existsByUsername(user.getUsername())) {
            return ResponseEntity.badRequest().body("Username already exists");
        }

        // Use the UserService to handle registration
        userService.register(user);
        return ResponseEntity.ok("Verification code sent to email");
    }

    @PostMapping("/verify")
    public ResponseEntity<?> verifyEmail(@RequestBody Map<String, String> request) {
        String email = request.get("email");
        String code = request.get("code");
        
        if (email == null || code == null) {
            return ResponseEntity.badRequest().body("Email and code are required");
        }

        Optional<User> userOptional = userRepository.findByEmail(email);
        if (!userOptional.isPresent()) {
            return ResponseEntity.badRequest().body("User not found");
        }

        User user = userOptional.get();
        if (user.isVerified()) {
            return ResponseEntity.badRequest().body("Email already verified");
        }

        if (user.getVerificationCode().equals(code)) {
            user.setVerified(true);
            userRepository.save(user);
            return ResponseEntity.ok(Map.of("message", "Email verified successfully"));
        }

        return ResponseEntity.badRequest().body("Invalid verification code");
    }

    @PostMapping("/resend-verification")
    public ResponseEntity<?> resendVerification(@RequestBody Map<String, String> request) {
        String email = request.get("email");
        if (email == null) {
            return ResponseEntity.badRequest().body(Map.of("message", "Email is required"));
        }
        try {
            boolean sent = userService.resendVerificationEmail(email);
            if (sent) {
                return ResponseEntity.ok().body(Map.of("message", "Verification email has been resent"));
        } else {
                return ResponseEntity.badRequest().body(Map.of("message", "User not found or already verified"));
            }
        } catch (Exception e) {
            logger.error("Error resending verification email: ", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("message", "Error resending verification email"));
        }
    }

    @PostMapping("/signin")
    public ResponseEntity<?> login(@RequestBody AuthRequest request) {
        Optional<User> userOptional = userRepository.findByEmail(request.getEmail());
            if (!userOptional.isPresent()) {
            return ResponseEntity.badRequest().body("User not found");
            }
            
            User user = userOptional.get();
            if (!user.isVerified()) {
            return ResponseEntity.badRequest().body("Email not verified");
            }
            
            if (!user.isApproved()) {
            return ResponseEntity.badRequest().body("Account not approved by admin");
        }

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            return ResponseEntity.badRequest().body("Invalid password");
        }

        String token = jwtUtil.generateToken(user.getEmail());
        return ResponseEntity.ok(new AuthResponse(token, user.getRole()));
    }

    @GetMapping("/check-user-status")
    public ResponseEntity<?> checkUserStatus(@RequestParam String email) {
        logger.info("Checking status for user: {}", email);
        
        try {
            Optional<User> userOptional = userRepository.findByEmail(email);
            if (!userOptional.isPresent()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND).body("User not found");
            }
            
            User user = userOptional.get();
            Map<String, Object> status = new HashMap<>();
            status.put("id", user.getId());
            status.put("email", user.getEmail());
            status.put("username", user.getUsername());
            status.put("verified", user.isVerified());
            status.put("approved", user.isApproved());
            status.put("role", user.getRole());
            
            return ResponseEntity.ok(status);
        } catch (Exception e) {
            logger.error("Error checking user status: ", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("Error checking user status: " + e.getMessage());
        }
    }

    /**
     * Temporary endpoint to get users pending approval
     * This is a workaround until the AdminController issue is fixed
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
     * Temporary endpoint to approve a user
     * This is a workaround until the AdminController issue is fixed
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

    @DeleteMapping("/delete-user")
    public ResponseEntity<?> deleteUserByEmail(@RequestParam String email) {
        logger.info("Deleting user with email: {}", email);
        
        try {
            if (!userRepository.existsByEmail(email)) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND).body("User not found");
            }
            
            userRepository.deleteByEmail(email);
            return ResponseEntity.ok("User deleted successfully");
        } catch (Exception e) {
            logger.error("Error deleting user: ", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("Error deleting user: " + e.getMessage());
        }
    }

    @PostMapping("/delete-unverified")
    public ResponseEntity<?> deleteUnverifiedUser(@RequestParam String email) {
        logger.info("Attempting to delete unverified user with email: {}", email);
        
        try {
            Optional<User> userOptional = userRepository.findByEmail(email);
            if (!userOptional.isPresent()) {
                return ResponseEntity.status(HttpStatus.NOT_FOUND).body("User not found");
            }
            
            User user = userOptional.get();
            if (user.isVerified()) {
                return ResponseEntity.badRequest().body("Cannot delete verified user");
            }
            
            userRepository.delete(user);
            return ResponseEntity.ok("User deleted successfully");
        } catch (Exception e) {
            logger.error("Error deleting unverified user: ", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("Error deleting user: " + e.getMessage());
        }
    }

    @GetMapping("/approved-users")
    public ResponseEntity<?> getApprovedUsers() {
        logger.info("Getting list of approved users");
        
        try {
            List<Map<String, Object>> approvedUsers = userRepository.findByVerifiedTrueAndApprovedTrue()
                .stream()
                .map(user -> {
                    Map<String, Object> userMap = new HashMap<>();
                    userMap.put("id", user.getId());
                    userMap.put("email", user.getEmail());
                    userMap.put("username", user.getUsername());
                    userMap.put("role", user.getRole());
                    // Include profile picture if available
                    if (user.getProfilePicture() != null && !user.getProfilePicture().isEmpty()) {
                        userMap.put("profilePicture", user.getProfilePicture());
                    }
                    return userMap;
                })
                .collect(Collectors.toList());
            
            logger.info("Found {} approved users", approvedUsers.size());
            return ResponseEntity.ok(approvedUsers);
        } catch (Exception e) {
            logger.error("Error getting approved users: {}", e.getMessage());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body("Error getting approved users: " + e.getMessage());
        }
    }

    @PostMapping("/forgot-password")
    public ResponseEntity<?> forgotPassword(@RequestBody Map<String, String> request) {
        String email = request.get("email");
        if (email == null) {
            return ResponseEntity.badRequest().body(Map.of("message", "Email is required"));
        }

        logger.info("Processing forgot password request for email: {}", email);

        Optional<User> userOptional = userRepository.findByEmail(email);
        if (!userOptional.isPresent()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("message", "User not found"));
        }

        User user = userOptional.get();
        String resetCode = String.format("%06d", new Random().nextInt(999999));
        user.setResetCode(resetCode);
        userRepository.save(user);

        try {
            emailService.sendPasswordResetEmail(email, resetCode);
            return ResponseEntity.ok(Map.of("message", "Reset code sent to your email"));
        } catch (Exception e) {
            logger.error("Failed to send reset code email", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(Map.of("message", "Failed to send reset code"));
        }
    }

    @PostMapping("/reset-password")
    public ResponseEntity<?> resetPassword(@RequestBody Map<String, String> request) {
        String email = request.get("email");
        String code = request.get("code");
        String newPassword = request.get("newPassword");

        if (email == null || code == null || newPassword == null) {
            return ResponseEntity.badRequest()
                .body(Map.of("message", "Email, code and new password are required"));
        }

        logger.info("Processing password reset request for email: {}", email);

        Optional<User> userOptional = userRepository.findByEmail(email);
        if (!userOptional.isPresent()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("message", "User not found"));
        }

        User user = userOptional.get();
        if (user.getResetCode() == null || !user.getResetCode().equals(code)) {
            return ResponseEntity.badRequest()
                .body(Map.of("message", "Invalid reset code"));
        }

        user.setPassword(passwordEncoder.encode(newPassword));
        user.setResetCode(null); // Clear the reset code after use
        userRepository.save(user);

        return ResponseEntity.ok(Map.of("message", "Password reset successfully"));
    }

    @PutMapping("/edit-profile")
    public ResponseEntity<?> editProfile(@RequestBody Map<String, String> request) {
        String email = request.get("email");
        String newUsername = request.get("username");
        String currentPassword = request.get("currentPassword");
        String newPassword = request.get("newPassword");
        String profilePicture = request.get("profilePicture");

        if (email == null) {
            return ResponseEntity.badRequest().body(Map.of("message", "Email is required"));
        }

        logger.info("Processing edit profile request for email: {}", email);

        Optional<User> userOptional = userRepository.findByEmail(email);
        if (!userOptional.isPresent()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("message", "User not found"));
        }

        User user = userOptional.get();

        // Update username if provided and different
        if (newUsername != null && !newUsername.isEmpty() && !newUsername.equals(user.getUsername())) {
            // Check if new username is already taken
            if (userRepository.existsByUsername(newUsername)) {
                return ResponseEntity.badRequest()
                    .body(Map.of("message", "Username already exists"));
            }
            user.setUsername(newUsername);
        }

        // Update password if both current and new passwords are provided
        if (currentPassword != null && newPassword != null) {
            if (!passwordEncoder.matches(currentPassword, user.getPassword())) {
                return ResponseEntity.badRequest()
                    .body(Map.of("message", "Current password is incorrect"));
            }
            user.setPassword(passwordEncoder.encode(newPassword));
        }
        
        // Update profile picture if provided
        if (profilePicture != null && !profilePicture.isEmpty()) {
            user.setProfilePicture(profilePicture);
        }

        userRepository.save(user);
        return ResponseEntity.ok(Map.of(
            "message", "Profile updated successfully",
            "username", user.getUsername(),
            "profilePicture", user.getProfilePicture() != null ? user.getProfilePicture() : ""
        ));
    }
}
