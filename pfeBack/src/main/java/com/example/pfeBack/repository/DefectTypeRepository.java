package com.example.pfeBack.repository;

import com.example.pfeBack.model.DefectType;
import org.springframework.data.mongodb.repository.MongoRepository;
import java.util.Optional;

public interface DefectTypeRepository extends MongoRepository<DefectType, String> {
    Optional<DefectType> findByDefectName(String defectName);
} 