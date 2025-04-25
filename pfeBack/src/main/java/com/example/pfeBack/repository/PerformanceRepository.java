package com.example.pfeBack.repository;

import com.example.pfeBack.model.Performance;
import org.springframework.data.mongodb.repository.MongoRepository;
import java.util.List;

public interface PerformanceRepository extends MongoRepository<Performance, String> {
    List<Performance> findByOrderRefAndDate(Integer orderRef, String date);
    List<Performance> findByDate(String date);
    List<Performance> findBySupervisorIdAndDate(String supervisorId, String date);
    List<Performance> findByWorkshopAndChainAndDate(String workshop, String chain, String date);
    List<Performance> findByWorkshopAndChain(String workshop, String chain);
}