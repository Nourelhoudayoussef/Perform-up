package com.example.pfeBack.dto;

import lombok.Data;
import java.util.List;

@Data
public class OpenRouterRequest {
    private String model = "mistralai/mixtral-8x7b";
    private List<Message> messages;

    @Data
    public static class Message {
        private String role;
        private String content;

        public Message(String role, String content) {
            this.role = role;
            this.content = content;
        }
    }
} 