package com.example.pfeBack.dto;

import lombok.Data;
import java.util.List;

@Data
public class OpenRouterResponse {
    private List<Choice> choices;

    @Data
    public static class Choice {
        private Message message;

        @Data
        public static class Message {
            private String content;
        }
    }
} 