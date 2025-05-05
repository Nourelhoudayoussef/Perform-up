package com.example.pfeBack.controller;

import com.example.pfeBack.service.ChatService;
import lombok.Data;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import reactor.core.publisher.Mono;

@RestController
@RequestMapping("/api")
@RequiredArgsConstructor
public class OpenRouterController {

    private final ChatService chatService;

    @PostMapping("/chat")
    public Mono<ResponseEntity<String>> chat(@RequestBody ChatRequest request) {
        return chatService.getChatResponse(request.getQuestion())
                .map(ResponseEntity::ok);
    }

    @Data
    public static class ChatRequest {
        private String question;
    }
} 