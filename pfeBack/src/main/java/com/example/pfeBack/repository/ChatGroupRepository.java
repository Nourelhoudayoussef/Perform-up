package com.example.pfeBack.repository;

import com.example.pfeBack.model.ChatGroup;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface ChatGroupRepository extends MongoRepository<ChatGroup, String> {
    List<ChatGroup> findByParticipantsContaining(String userId);
    List<ChatGroup> findByCreatorId(String creatorId);
    List<ChatGroup> findByTitleContainingIgnoreCase(String name);
} 