package com.example.pfeBack.repository;

import com.example.pfeBack.model.Message;
import org.springframework.data.mongodb.repository.MongoRepository;
import java.time.LocalDateTime;
import java.util.List;

public interface MessageRepository extends MongoRepository<Message, String> {
    List<Message> findByChatGroupIdOrderByTimestampAsc(String chatGroupId);
    List<Message> findByChatGroupIdAndTimestampAfterOrderByTimestampAsc(String chatGroupId, LocalDateTime timestamp);
    int countByChatGroupIdAndTimestampAfter(String chatGroupId, LocalDateTime timestamp);
    List<Message> findByChatGroupIdAndTimestampAfter(String chatGroupId, LocalDateTime timestamp);
    
    // Find the most recent message in a chat group
    Message findTopByChatGroupIdOrderByTimestampDesc(String chatGroupId);
}