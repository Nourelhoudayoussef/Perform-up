package com.example.pfeBack.controller;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/supervisor")
public class SupervisorController {

    @GetMapping("/monitor")
    @PreAuthorize("hasRole('SUPERVISOR')")
    public String getSupervisorPage() {
        return "Supervisor Access Granted!";
    }
}
