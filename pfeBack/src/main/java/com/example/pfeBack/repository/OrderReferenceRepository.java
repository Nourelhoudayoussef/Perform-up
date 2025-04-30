package com.example.pfeBack.repository;

import com.example.pfeBack.model.OrderReference;
import org.springframework.data.mongodb.repository.MongoRepository;
import java.util.Optional;

public interface OrderReferenceRepository extends MongoRepository<OrderReference, String> {
    Optional<OrderReference> findByOrderRef(Integer orderRef);
} 