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
    
    // Set target by date and orderRef
    @PostMapping("/target")
    @PreAuthorize("hasRole('SUPERVISOR')")
    public ResponseEntity<?> setTarget(@RequestParam Integer orderRef, @RequestParam int target) {
        String today = java.time.LocalDate.now().toString();
        Performance newPerformance = new Performance();
        newPerformance.setOrderRef(orderRef);
        newPerformance.setDate(today);
        newPerformance.setProductionTarget(target);
        newPerformance.setProduced(0);
        newPerformance.setDefectList(new ArrayList<>());
        newPerformance.setWorkshop(null);
        newPerformance.setChain(null);
        newPerformance.setHour(null);
        newPerformance.setSupervisorId(null);
        performanceRepository.save(newPerformance);
        return ResponseEntity.ok("Target set and performance record created");
    }

    // Get daily performance with filters
    @GetMapping("/performance")
    @PreAuthorize("hasRole('SUPERVISOR')")
    public ResponseEntity<List<Performance>> getPerformance(
            @RequestParam(required = false) String date,
            @RequestParam(required = false) Integer orderRef,
            @RequestParam(required = false) Integer workshop,
            @RequestParam(required = false) Integer chain) {
        List<Performance> performances = performanceRepository.findAll();
        if (date != null) {
            performances = performances.stream().filter(p -> p.getDate().equals(date)).toList();
        }
        if (orderRef != null) {
            performances = performances.stream().filter(p -> p.getOrderRef() != null && p.getOrderRef().equals(orderRef)).toList();
        }
        if (workshop != null) {
            performances = performances.stream().filter(p -> p.getWorkshop() != null && p.getWorkshop().equals("Workshop " + workshop)).toList();
        }
        if (chain != null) {
            performances = performances.stream().filter(p -> p.getChain() != null && p.getChain().equals("Chain " + chain)).toList();
        }
        return ResponseEntity.ok(performances);
    }

    // Record performance data (workshop and chain as int, no productionTarget)
    @PostMapping("/performance")
    @PreAuthorize("hasRole('SUPERVISOR')")
    public ResponseEntity<?> recordPerformance(@RequestBody PerformanceDTO performanceDTO, Authentication authentication) {
        String today = java.time.LocalDate.now().toString();
        Optional<User> supervisorOpt = userRepository.findByEmail(authentication.getName());
        if (!supervisorOpt.isPresent()) {
            return ResponseEntity.badRequest().body("Supervisor not found");
        }
        User supervisor = supervisorOpt.get();
        if (performanceDTO.getWorkshopInt() < 1 || performanceDTO.getWorkshopInt() > 3 || performanceDTO.getChainInt() < 1 || performanceDTO.getChainInt() > 3) {
            return ResponseEntity.badRequest().body("Invalid workshop or chain. Must be 1, 2, or 3");
        }
        if (!isValidHourFormat(performanceDTO.getHour())) {
            return ResponseEntity.badRequest().body("Invalid hour format. Expected format between 08:00 and 16:00");
        }
        String workshopStr = "Workshop " + performanceDTO.getWorkshopInt();
        String chainStr = "Chain " + performanceDTO.getChainInt();
        List<Defect> defects = new ArrayList<>();
        if (performanceDTO.getDefectList() != null) {
            for (DefectDTO defectDTO : performanceDTO.getDefectList()) {
                defects.add(new Defect(defectDTO.getDefectType(), defectDTO.getCount()));
            }
        }
        Performance performance = new Performance(
                supervisor.getId(),
            today,
                performanceDTO.getHour(),
            workshopStr,
            chainStr,
                performanceDTO.getProduced(),
                defects,
            0, // productionTarget defaulted to 0
                performanceDTO.getOrderRef()
            );
        performanceRepository.save(performance);
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
