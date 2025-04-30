package com.example.pfeBack.dto;

public class TechnicianStatsDTO {
    private int totalInterventions;
    private int totalTimeSpent;
    private long machinesChecked;
    
    // Constructors
    public TechnicianStatsDTO() {}
    
    public TechnicianStatsDTO(int totalInterventions, int totalTimeSpent, long machinesChecked) {
        this.totalInterventions = totalInterventions;
        this.totalTimeSpent = totalTimeSpent;
        this.machinesChecked = machinesChecked;
    }
    
    // Getters and Setters
    public int getTotalInterventions() {
        return totalInterventions;
    }
    
    public void setTotalInterventions(int totalInterventions) {
        this.totalInterventions = totalInterventions;
    }
    
    public int getTotalTimeSpent() {
        return totalTimeSpent;
    }
    
    public void setTotalTimeSpent(int totalTimeSpent) {
        this.totalTimeSpent = totalTimeSpent;
    }
    
    public long getMachinesChecked() {
        return machinesChecked;
    }
    
    public void setMachinesChecked(long machinesChecked) {
        this.machinesChecked = machinesChecked;
    }
} 