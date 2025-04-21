package com.example.pfeBack.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

import com.example.pfeBack.model.User;
import com.example.pfeBack.repository.UserRepository;
import java.util.Random;
import java.util.Optional;

@Service
public class UserService {
    private final UserRepository userRepository;
    private final EmailService emailService;
    private final PasswordEncoder passwordEncoder = new BCryptPasswordEncoder();
    private static final Logger logger = LoggerFactory.getLogger(UserService.class);

    public UserService(UserRepository userRepository, EmailService emailService) {
        this.userRepository = userRepository;
        this.emailService = emailService;
    }

    public void register(User user) {
        user.setPassword(passwordEncoder.encode(user.getPassword())); // Hash password
        String verificationCode = generateVerificationCode();
        user.setVerificationCode(verificationCode);
        user.setVerified(false); // Not verified yet
        user.setApproved(false); // Explicitly set to not approved
        userRepository.save(user);

        // Send verification email
        emailService.sendVerificationEmail(user.getEmail(), verificationCode);
    }

    private String generateVerificationCode() {
        return String.valueOf(new Random().nextInt(900000) + 100000); // 6-digit code
    }

    public User getUserById(String id) {
        return userRepository.findById(id).orElse(null);
    }

    public User createUser(User user) {
        return userRepository.save(user);
    }

    public User updateUser(String id, User user) {
        Optional<User> existingUser = userRepository.findById(id);
        if (existingUser.isPresent()) {
            user.setId(id);
            return userRepository.save(user);
        }
        return null;
    }

    public boolean deleteUser(String id) {
        if (userRepository.existsById(id)) {
            userRepository.deleteById(id);
            return true;
        }
        return false;
    }

    public boolean resendVerificationEmail(String email) {
        try {
            logger.info("Attempting to resend verification email to: {}", email);
            logger.info("Checking if user exists in database...");
            User user = userRepository.findByEmail(email).orElse(null);
            if (user == null) {
                logger.warn("User not found with email: {}", email);
                return false;
            }
            logger.info("Found user with email: {}, verified: {}, approved: {}, verification code: {}", 
                email, user.isVerified(), user.isApproved(), user.getVerificationCode());
            if (user.isVerified()) {
                logger.warn("User is already verified: {}", email);
                return false;
            }
            String newVerificationCode = generateVerificationCode();
            logger.info("Generated new verification code: {}", newVerificationCode);
            user.setVerificationCode(newVerificationCode);
            userRepository.save(user);
            logger.info("Updated verification code for user: {}", email);
            try {
                emailService.sendVerificationEmail(user.getEmail(), newVerificationCode);
                logger.info("Successfully resent verification email to: {}", email);
                return true;
            } catch (Exception e) {
                logger.error("Failed to send verification email: {}", e.getMessage(), e);
                throw e;
            }
        } catch (Exception e) {
            logger.error("Error in resendVerificationEmail for email: {}", email, e);
            throw new RuntimeException("Failed to resend verification email: " + e.getMessage());
        }
    }
}
