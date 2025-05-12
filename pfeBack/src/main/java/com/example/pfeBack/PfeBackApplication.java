package com.example.pfeBack;

import com.example.pfeBack.model.User;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.domain.EntityScan;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ComponentScan;
import org.springframework.data.mongodb.repository.config.EnableMongoRepositories;
import com.example.pfeBack.repository.UserRepository;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.util.List;
import java.util.Optional;
import java.util.Scanner;

@SpringBootApplication
@ComponentScan(basePackages = {"com.example.pfeBack", "com.pfeBack"})
@EnableMongoRepositories(basePackages = {"com.example.pfeBack.repository"})
@EntityScan(basePackages = {"com.example.pfeBack.model"})
public class PfeBackApplication {

	public static void main(String[] args) {
		SpringApplication.run(PfeBackApplication.class, args);
	}
	
	@Bean
	public RestTemplate restTemplate() {
		return new RestTemplate();
	}
	
	@Bean
	public CommandLineRunner initializeDefaultAdmin(UserRepository userRepository, PasswordEncoder passwordEncoder) {
		return args -> {
			// Default admin credentials
			String adminEmail = "admin@factory.com";
			String adminPassword = "Admin123!";
			
			// Check if admin already exists
			if (!userRepository.findByEmail(adminEmail).isPresent()) {
				System.out.println("Creating default admin user: " + adminEmail);
				
				// Create admin user
				User adminUser = new User();
				adminUser.setEmail(adminEmail);
				adminUser.setUsername("admin");
				adminUser.setPassword(passwordEncoder.encode(adminPassword));
				adminUser.setRole("ADMIN");
				adminUser.setVerified(true);
				adminUser.setApproved(true);
				
				// Save admin user
				userRepository.save(adminUser);
				
				System.out.println("Default admin user created successfully!");
				System.out.println("Email: " + adminEmail);
				System.out.println("Password: " + adminPassword);
			} else {
				System.out.println("Default admin user already exists.");
			}
		};
	}
	
	@Bean
	public CommandLineRunner listPendingUsers(UserRepository userRepository) {
		return args -> {
			System.out.println("\n=== USERS PENDING APPROVAL ===");
			List<User> pendingUsers = userRepository.findByVerifiedTrueAndApprovedFalse();
			
			if (pendingUsers.isEmpty()) {
				System.out.println("No users pending approval.");
			} else {
				System.out.println("Found " + pendingUsers.size() + " users pending approval:");
				for (User user : pendingUsers) {
					System.out.println("ID: " + user.getId());
					System.out.println("Email: " + user.getEmail());
					System.out.println("Username: " + user.getUsername());
					System.out.println("Role: " + user.getRole());
					System.out.println("---");
				}
				
				// Prompt to approve a user
				System.out.println("\nTo approve a user, enter their ID or press Enter to skip:");
				@SuppressWarnings("resource")
				Scanner scanner = new Scanner(System.in);
				String userId = scanner.nextLine().trim();
				
				if (!userId.isEmpty()) {
					Optional<User> userOptional = userRepository.findById(userId);
					if (userOptional.isPresent()) {
						User user = userOptional.get();
						user.setApproved(true);
						userRepository.save(user);
						System.out.println("User approved successfully: " + user.getEmail());
					} else {
						System.out.println("User not found with ID: " + userId);
					}
				}
			}
		};
	}

	@Bean
	public WebMvcConfigurer corsConfigurer() {
		return new WebMvcConfigurer() {
			@Override
			public void addCorsMappings(CorsRegistry registry) {
				registry.addMapping("/**")
						.allowedOrigins("*")
						.allowedMethods("GET", "POST", "PUT", "DELETE", "OPTIONS")
						.allowedHeaders("*")
						.maxAge(3600);
			}
		};
	}
}
