package com.example.pfeBack.controller;

import com.example.pfeBack.dto.DailyTargetRequestDTO;
import com.example.pfeBack.dto.DefectDTO;
import com.example.pfeBack.dto.PerformanceDTO;
import com.example.pfeBack.model.Defect;
import com.example.pfeBack.model.OrderReference;
import com.example.pfeBack.model.Performance;
import com.example.pfeBack.model.User;
import com.example.pfeBack.repository.DefectTypeRepository;
import com.example.pfeBack.repository.OrderReferenceRepository;
import com.example.pfeBack.repository.PerformanceRepository;
import com.example.pfeBack.repository.UserRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.regex.Pattern;

@RestController
@RequestMapping("/supervisor")
public class SupervisorController {

    @Autowired
    private PerformanceRepository performanceRepository;
    
    @Autowired
    private OrderReferenceRepository orderReferenceRepository;
    
    @Autowired
    private DefectTypeRepository defectTypeRepository;
    
    @Autowired
    private WebSocketController webSocketController;
    
    @Autowired
    private UserRepository userRepository;
    
    // Set daily target for a product
    @PostMapping("/target")
    @PreAuthorize("hasRole('SUPERVISOR')")
    public ResponseEntity<?> setDailyTarget(@RequestBody DailyTargetRequestDTO targetDTO, Authentication authentication) {
        // Validate order reference
        Optional<OrderReference> orderRef = orderReferenceRepository.findByOrderRef(targetDTO.getOrderRef());
        if (!orderRef.isPresent()) {
            return ResponseEntity.badRequest().body("Invalid order reference");
        }
        
        // Get supervisor info
        Optional<User> supervisorOpt = userRepository.findByEmail(authentication.getName());
        if (!supervisorOpt.isPresent()) {
            return ResponseEntity.badRequest().body("Supervisor not found");
        }
        
        User supervisor = supervisorOpt.get();
        
        // Create or update performance entries for all hours of operation (8:00 AM to 4:00 PM)
        String[] operationHours = {"08:00", "09:00", "10:00", "11:00", "12:00", "13:00", "14:00", "15:00", "16:00"};
        
        for (String hour : operationHours) {
            // Check if entry already exists
            List<Performance> existingPerformances = performanceRepository.findByOrderRefAndDate(targetDTO.getOrderRef(), targetDTO.getDate());
            
            boolean hourExists = existingPerformances.stream()
                .anyMatch(p -> p.getHour().equals(hour));
            
            if (!hourExists) {
                // For each workshop and chain combination
                for (int workshop = 1; workshop <= 3; workshop++) {
                    for (int chain = 1; chain <= 3; chain++) {
                        Performance performance = new Performance(
                            supervisor.getId(),
                            targetDTO.getDate(),
                            hour,
                            "Workshop " + workshop,
                            "Chain " + chain,
                            0, // No production yet
                            0, // No defects yet
                            "", // No defect name yet
                            targetDTO.getTargetQuantity(),
                            targetDTO.getOrderRef()
                        );
                        performanceRepository.save(performance);
                    }
                }
            } else {
                // Update target quantity for existing entries
                for (Performance performance : existingPerformances) {
                    performance.setProductionTarget(targetDTO.getTargetQuantity());
                    performanceRepository.save(performance);
                }
            }
        }
        
        // Notify clients that targets have been updated
        webSocketController.broadcastTargetUpdate(targetDTO.getDate(), targetDTO);
        
        return ResponseEntity.ok("Daily target set successfully");
    }

    // Get daily performance for a specific date
    @GetMapping("/performance/{date}")
    @PreAuthorize("hasRole('SUPERVISOR')")
    public ResponseEntity<List<Performance>> getDailyPerformance(@PathVariable String date) {
        List<Performance> performances = performanceRepository.findByDate(date);
        return ResponseEntity.ok(performances);
    }

    // Get performance by workshop and chain (only for current day)
    @GetMapping("/performance/workshop/{workshop}/chain/{chain}")
    @PreAuthorize("hasRole('SUPERVISOR')")
    public ResponseEntity<List<Performance>> getPerformanceByWorkshopAndChain(
            @PathVariable int workshop,
            @PathVariable int chain) {
        String workshopFormat = "Workshop " + workshop;
        String chainFormat = "Chain " + chain;
        
        // Get current date in the format "yyyy-MM-dd"
        String today = java.time.LocalDate.now().toString();
        
        List<Performance> performances = performanceRepository.findByWorkshopAndChainAndDate(
            workshopFormat, chainFormat, today);
        return ResponseEntity.ok(performances);
    }

    // Record performance data
    @PostMapping("/performance")
    @PreAuthorize("hasRole('SUPERVISOR')")
    public ResponseEntity<?> recordPerformance(@RequestBody PerformanceDTO performanceDTO, Authentication authentication) {
        // Validate order reference
        Optional<OrderReference> orderRef = orderReferenceRepository.findByOrderRef(performanceDTO.getOrderRef());
        if (!orderRef.isPresent()) {
            return ResponseEntity.badRequest().body("Invalid order reference");
        }
        
        // Get supervisor info
        Optional<User> supervisorOpt = userRepository.findByEmail(authentication.getName());
        if (!supervisorOpt.isPresent()) {
            return ResponseEntity.badRequest().body("Supervisor not found");
        }
        
        User supervisor = supervisorOpt.get();
        
        // Validate workshop and chain format
        if (!isValidWorkshopFormat(performanceDTO.getWorkshop()) || !isValidChainFormat(performanceDTO.getChain())) {
            return ResponseEntity.badRequest().body("Invalid workshop or chain format. Expected 'Workshop X' and 'Chain Y'");
        }
        
        // Validate hour format (8:00 AM to 4:00 PM)
        if (!isValidHourFormat(performanceDTO.getHour())) {
            return ResponseEntity.badRequest().body("Invalid hour format. Expected format between 08:00 and 16:00");
        }
        
        // Always use current date in format YYYY-MM-DD
        String today = java.time.LocalDate.now().toString();
        
        // Find existing performance record or create new one
        List<Performance> existingPerformances = performanceRepository.findByWorkshopAndChainAndDate(
            performanceDTO.getWorkshop(), 
            performanceDTO.getChain(), 
            today
        );
        
        Performance performance = null;
        
        for (Performance existing : existingPerformances) {
            if (existing.getHour().equals(performanceDTO.getHour()) && 
                existing.getOrderRef().equals(performanceDTO.getOrderRef())) {
                performance = existing;
                break;
            }
        }
        
        // Convert DefectDTO list to Defect list
        List<Defect> defects = new ArrayList<>();
        if (performanceDTO.getDefectList() != null) {
            for (DefectDTO defectDTO : performanceDTO.getDefectList()) {
                defects.add(new Defect(defectDTO.getDefectType(), defectDTO.getCount()));
            }
        }
        
        if (performance == null) {
            // Create new performance record using the constructor with defect list
            performance = new Performance(
                supervisor.getId(),
                today,  // Use today's date
                performanceDTO.getHour(),
                performanceDTO.getWorkshop(),
                performanceDTO.getChain(),
                performanceDTO.getProduced(),
                defects,
                performanceDTO.getProductionTarget(),
                performanceDTO.getOrderRef()
            );
        } else {
            // Update existing performance record
            performance.setProduced(performanceDTO.getProduced());
            performance.setDefectList(defects);
        }
        
        performanceRepository.save(performance);
        
        // Notify clients about the updated performance data
        webSocketController.broadcastPerformanceUpdate(performance);
        
        return ResponseEntity.ok("Performance data recorded successfully");
    }

    // Helper methods for validation
    private boolean isValidWorkshopFormat(String workshop) {
        Pattern pattern = Pattern.compile("^Workshop [1-3]$");
        return pattern.matcher(workshop).matches();
    }
    
    private boolean isValidChainFormat(String chain) {
        Pattern pattern = Pattern.compile("^Chain [1-3]$");
        return pattern.matcher(chain).matches();
    }
    
    private boolean isValidHourFormat(String hour) {
        try {
            LocalTime time = LocalTime.parse(hour, DateTimeFormatter.ofPattern("HH:mm"));
            LocalTime start = LocalTime.of(8, 0);
            LocalTime end = LocalTime.of(16, 0);
            return !time.isBefore(start) && !time.isAfter(end);
        } catch (Exception e) {
            return false;
        }
    }
}
