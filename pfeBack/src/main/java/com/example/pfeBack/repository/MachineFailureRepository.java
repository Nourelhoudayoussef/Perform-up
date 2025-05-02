package com.example.pfeBack.repository;

import com.example.pfeBack.model.MachineFailure;
import org.springframework.data.mongodb.repository.MongoRepository;
import org.springframework.data.mongodb.repository.Query;
import java.util.List;

public interface MachineFailureRepository extends MongoRepository<MachineFailure, String> {
    @Query("{ 'technician_id' : ?0 }")
    List<MachineFailure> findByTechnician_id(String technician_id);
    
    List<MachineFailure> findByMachineReference(String machineReference);
    
    @Query("{ 'technician_id' : ?0, 'date' : ?1 }")
    List<MachineFailure> findByTechnician_idAndDate(String technician_id, String date);
    
    List<MachineFailure> findByDate(String date);
}