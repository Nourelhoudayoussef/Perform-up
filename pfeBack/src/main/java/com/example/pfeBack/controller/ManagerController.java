package com.example.pfeBack.controller;

import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/manager")
public class ManagerController {

    @GetMapping("/dashboard")
    @PreAuthorize("hasRole('MANAGER')")
    public String getManagerDashboard() {
        return "Manager Dashboard Access Granted!";
    }
}
