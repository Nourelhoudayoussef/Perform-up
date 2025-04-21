package com.example.pfeBack.controller;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/technician")
public class TechnicianController {

    @GetMapping("/alerts")
    @PreAuthorize("hasRole('TECHNICIAN')")
    public String getTechnicianAlerts() {
        return "Technician Alert Page!";
    }
}
