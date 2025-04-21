package com.example.pfeBack.repository;

import java.util.List;

import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.stereotype.Repository;

import com.example.pfeBack.model.Notification;

@Repository
public interface NotificationRepository extends MongoRepository<Notification, String> {
    List<Notification> findByRecipientIdsContainingOrderByCreatedAtDesc(String recipientId);
    List<Notification> findBySenderIdOrderByCreatedAtDesc(String senderId);
    List<Notification> findByRecipientIdsContainingAndIsReadFalse(String recipientId);
    void deleteByRecipientIdsContaining(String recipientId);
} 