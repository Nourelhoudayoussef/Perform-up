package com.example.pfeBack.service;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.stereotype.Service;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.mail.MailAuthenticationException;
import org.springframework.mail.MailSendException;
import org.springframework.mail.MailException;
import org.springframework.beans.factory.annotation.Value;

@Service
public class EmailService {
    private static final Logger logger = LoggerFactory.getLogger(EmailService.class);

    @Autowired
    private JavaMailSender mailSender;

    @Value("${spring.mail.host}")
    private String mailHost;

    @Value("${spring.mail.port}")
    private String mailPort;

    @Value("${spring.mail.username}")
    private String mailUsername;

    public void sendVerificationEmail(String to, String verificationCode) {
        logger.info("Attempting to send verification email to: {}", to);
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(mailUsername); // Set the from address
            message.setTo(to);
            message.setSubject("Email Verification");
            message.setText("Your verification code is: " + verificationCode);
            
            logger.info("Email configuration: host={}, port={}, username={}", 
                mailHost, mailPort, mailUsername);
            
            mailSender.send(message);
            logger.info("Verification email sent successfully to: {}", to);
        } catch (MailAuthenticationException e) {
            logger.error("Authentication failed while sending verification email to: {}. Error: {}", to, e.getMessage(), e);
            throw new RuntimeException("Email authentication failed. Please check your email credentials.", e);
        } catch (MailSendException e) {
            logger.error("Failed to send verification email to: {}. Error: {}", to, e.getMessage(), e);
            throw new RuntimeException("Failed to send email. Please check your internet connection and SMTP settings.", e);
        } catch (MailException e) {
            logger.error("Unexpected error while sending verification email to: {}. Error: {}", to, e.getMessage(), e);
            throw new RuntimeException("An unexpected error occurred while sending the email.", e);
        }
    }

    public void sendApprovalEmail(String to, boolean approved) {
        logger.info("Attempting to send approval email to: {}", to);
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(mailUsername); // Set the from address
            message.setTo(to);
            message.setSubject("Account Status Update");
            message.setText(approved ? "Your account has been approved!" : "Your account has been rejected.");
            
            logger.info("Email configuration: host={}, port={}, username={}", 
                mailHost, mailPort, mailUsername);
            
            mailSender.send(message);
            logger.info("Approval email sent successfully to: {}", to);
        } catch (MailAuthenticationException e) {
            logger.error("Authentication failed while sending approval email to: {}. Error: {}", to, e.getMessage(), e);
            throw new RuntimeException("Email authentication failed. Please check your email credentials.", e);
        } catch (MailSendException e) {
            logger.error("Failed to send approval email to: {}. Error: {}", to, e.getMessage(), e);
            throw new RuntimeException("Failed to send email. Please check your internet connection and SMTP settings.", e);
        } catch (MailException e) {
            logger.error("Unexpected error while sending approval email to: {}. Error: {}", to, e.getMessage(), e);
            throw new RuntimeException("An unexpected error occurred while sending the email.", e);
        }
    }

    public void sendPasswordResetEmail(String to, String resetCode) {
        logger.info("Attempting to send password reset email to: {}", to);
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom(mailUsername); // Set the from address
            message.setTo(to);
            message.setSubject("Password Reset Code");
            message.setText("Your password reset code is: " + resetCode + "\n\n" +
                          "If you did not request a password reset, please ignore this email.");
            
            logger.info("Email configuration: host={}, port={}, username={}", 
                mailHost, mailPort, mailUsername);
            
            mailSender.send(message);
            logger.info("Password reset email sent successfully to: {}", to);
        } catch (MailAuthenticationException e) {
            logger.error("Authentication failed while sending password reset email to: {}. Error: {}", to, e.getMessage(), e);
            throw new RuntimeException("Email authentication failed. Please check your email credentials.", e);
        } catch (MailSendException e) {
            logger.error("Failed to send password reset email to: {}. Error: {}", to, e.getMessage(), e);
            throw new RuntimeException("Failed to send email. Please check your internet connection and SMTP settings.", e);
        } catch (MailException e) {
            logger.error("Unexpected error while sending password reset email to: {}. Error: {}", to, e.getMessage(), e);
            throw new RuntimeException("An unexpected error occurred while sending the email.", e);
        }
    }
}
