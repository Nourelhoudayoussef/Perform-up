package com.example.pfeBack.config;

import io.netty.resolver.dns.DnsNameResolverBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.reactive.ReactorClientHttpConnector;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.netty.http.client.HttpClient;
import reactor.netty.resources.ConnectionProvider;

import java.time.Duration;

@Configuration
public class OpenRouterConfig {

    @Bean
    public WebClient openRouterWebClient() {
        HttpClient httpClient = HttpClient.create()
                .resolver(spec -> spec
                        .queryTimeout(Duration.ofSeconds(10))
                        .build())
                .responseTimeout(Duration.ofSeconds(30));

        return WebClient.builder()
                .baseUrl("https://openrouter.ai/api/v1")
                .defaultHeader("Authorization", "Bearer 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")
                .defaultHeader("HTTP-Referer", "http://localhost:8080")
                .defaultHeader("X-Title", "PFE App")
                .clientConnector(new ReactorClientHttpConnector(httpClient))
                .build();
    }
} 