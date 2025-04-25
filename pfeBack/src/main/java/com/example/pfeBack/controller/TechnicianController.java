package com.example.pfeBack.controller;

import com.example.pfeBack.dto.MachineFailureDTO;
import com.example.pfeBack.dto.TechnicianStatsDTO;
import com.example.pfeBack.model.MachineFailure;
import com.example.pfeBack.model.User;
import com.example.pfeBack.repository.MachineFailureRepository;
import com.example.pfeBack.repository.UserRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import java.util.regex.Pattern;

@RestController
@RequestMapping("/technician")
public class TechnicianController {

    @Autowired
    private MachineFailureRepository machineFailureRepository;
    
    @Autowired
    private UserRepository userRepository;
    
    @Autowired
    private WebSocketController webSocketController;

    // Record a machine intervention
    @PostMapping("/intervention")
    @PreAuthorize("hasRole('TECHNICIAN')")
    public ResponseEntity<?> recordIntervention(@RequestBody MachineFailureDTO failureDTO, Authentication authentication) {
        // Validate machine reference format (W-C-M)
        if (!isValidMachineReference(failureDTO.getMachineReference())) {
            return ResponseEntity.badRequest().body("Invalid machine reference format. Expected format: W(workshop)-C(chain)-M(machine)");
        }
        
        // Get technician info
        Optional<User> technicianOpt = userRepository.findByEmail(authentication.getName());
        if (!technicianOpt.isPresent()) {
            return ResponseEntity.badRequest().body("Technician not found");
        }
        
        User technician = technicianOpt.get();
        
        // Create and save the machine failure
        MachineFailure failure = new MachineFailure(
            failureDTO.getDate(),
            failureDTO.getTimeTaken(), // Using timeTaken as timeSpent
            technician.getId(),
            technician.getUsername(),
            failureDTO.getMachineReference(),
            failureDTO.getDescription()
        );
        
        machineFailureRepository.save(failure);
        
        // Notify clients about the new intervention
        webSocketController.broadcastInterventionUpdate(failure);
        
        return ResponseEntity.ok("Intervention recorded successfully");
    }

    // Get technician's interventions for a specific date
    @GetMapping("/interventions/{date}")
    @PreAuthorize("hasRole('TECHNICIAN')")
    public ResponseEntity<List<MachineFailure>> getInterventions(@PathVariable String date, Authentication authentication) {
        Optional<User> technicianOpt = userRepository.findByEmail(authentication.getName());
        if (!technicianOpt.isPresent()) {
            return ResponseEntity.badRequest().build();
        }
        
        List<MachineFailure> interventions = machineFailureRepository
            .findByTechnician_idAndDate(technicianOpt.get().getId(), date);
        
        return ResponseEntity.ok(interventions);
    }

    // Get technician's interventions for today
    @GetMapping("/interventions")
    @PreAuthorize("hasRole('TECHNICIAN')")
    public ResponseEntity<List<MachineFailure>> getTodayInterventions(Authentication authentication) {
        Optional<User> technicianOpt = userRepository.findByEmail(authentication.getName());
        if (!technicianOpt.isPresent()) {
            return ResponseEntity.badRequest().build();
        }
        
        // Get current date in the format "yyyy-MM-dd"
        String today = java.time.LocalDate.now().toString();
        
        List<MachineFailure> interventions = machineFailureRepository
            .findByTechnician_idAndDate(technicianOpt.get().getId(), today);
        
        return ResponseEntity.ok(interventions);
    }

    // Get intervention statistics
    @GetMapping("/statistics/{date}")
    @PreAuthorize("hasRole('TECHNICIAN')")
    public ResponseEntity<TechnicianStatsDTO> getStatistics(@PathVariable String date, Authentication authentication) {
        Optional<User> technicianOpt = userRepository.findByEmail(authentication.getName());
        if (!technicianOpt.isPresent()) {
            return ResponseEntity.badRequest().build();
        }
        
        List<MachineFailure> interventions = machineFailureRepository
            .findByTechnician_idAndDate(technicianOpt.get().getId(), date);
        
        int totalInterventions = interventions.size();
        int totalTime = interventions.stream().mapToInt(MachineFailure::getTimeSpent).sum();
        long uniqueMachines = interventions.stream()
            .map(MachineFailure::getMachineReference)
            .distinct()
            .count();
        
        TechnicianStatsDTO stats = new TechnicianStatsDTO(
            totalInterventions,
            totalTime,
            uniqueMachines
        );
        
        return ResponseEntity.ok(stats);
    }

    // Get intervention statistics for today
    @GetMapping("/statistics")
    @PreAuthorize("hasRole('TECHNICIAN')")
    public ResponseEntity<TechnicianStatsDTO> getTodayStatistics(Authentication authentication) {
        Optional<User> technicianOpt = userRepository.findByEmail(authentication.getName());
        if (!technicianOpt.isPresent()) {
            return ResponseEntity.badRequest().build();
        }
        
        // Get current date in the format "yyyy-MM-dd"
        String today = java.time.LocalDate.now().toString();
        
        List<MachineFailure> interventions = machineFailureRepository
            .findByTechnician_idAndDate(technicianOpt.get().getId(), today);
        
        int totalInterventions = interventions.size();
        int totalTime = interventions.stream().mapToInt(MachineFailure::getTimeSpent).sum();
        long uniqueMachines = interventions.stream()
            .map(MachineFailure::getMachineReference)
            .distinct()
            .count();
        
        TechnicianStatsDTO stats = new TechnicianStatsDTO(
            totalInterventions,
            totalTime,
            uniqueMachines
        );
        
        return ResponseEntity.ok(stats);
    }

    // Helper method to validate machine reference format (W-C-M)
    private boolean isValidMachineReference(String reference) {
        Pattern pattern = Pattern.compile("^W[1-3]-C[1-3]-M[1-9]\\d*$");
        return pattern.matcher(reference).matches();
    }
}
