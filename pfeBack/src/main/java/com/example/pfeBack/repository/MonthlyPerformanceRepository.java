package com.example.pfeBack.repository;

import com.example.pfeBack.model.MonthlyPerformance;
import org.springframework.data.mongodb.repository.MongoRepository;
import java.util.Optional;
import java.util.List;

public interface MonthlyPerformanceRepository extends MongoRepository<MonthlyPerformance, String> {
    Optional<MonthlyPerformance> findByMonthAndOrderRef(String month, String orderRef);
    List<MonthlyPerformance> findByMonth(String month);
    List<MonthlyPerformance> findByOrderRef(String orderRef);
} 