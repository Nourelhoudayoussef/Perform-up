package com.example.pfeBack.repository;

import com.example.pfeBack.model.User;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface UserRepository extends MongoRepository<User, String> {
    Optional<User> findByEmail(String email);
    Optional<User> findByUsername(String username);
    boolean existsByEmail(String email);
    boolean existsByUsername(String username);
    List<User> findByVerifiedTrueAndApprovedFalse();
    List<User> findByVerifiedTrueAndApprovedTrue();
    void deleteByEmail(String email);
    
    // Add method to search users by username containing the search term
    List<User> findByUsernameContainingIgnoreCaseAndVerifiedTrueAndApprovedTrue(String username);
    
    // Find users that are not members of a specific group
    List<User> findByIdNotInAndVerifiedTrueAndApprovedTrue(List<String> memberIds);
    
    // Find users by role
    List<User> findByRole(String role);
}
