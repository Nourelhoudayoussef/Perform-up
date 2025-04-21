package com.example.pfeBack.service;

import com.example.pfeBack.model.User;
import com.example.pfeBack.repository.UserRepository;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
public class UserDetailsServiceImpl implements UserDetailsService {

    private final UserRepository userRepository;

    public UserDetailsServiceImpl(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        // In this context, 'username' is actually the email
        User user = userRepository.findByEmail(username)
                .orElseThrow(() -> new UsernameNotFoundException("User not found with email: " + username));

        // Check if the user is verified and approved
        if (!user.isVerified()) {
            throw new UsernameNotFoundException("User email not verified: " + username);
        }
        
        if (!user.isApproved()) {
            throw new UsernameNotFoundException("User not approved by admin: " + username);
        }

        return org.springframework.security.core.userdetails.User
                .withUsername(username) // Use email as the username
                .password(user.getPassword()) // Hashed password
                .roles(user.getRole()) // Role-based authentication
                .build();
    }
}
