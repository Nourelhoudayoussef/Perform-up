package com.example.pfeBack.dto;

public class MachineFailureDTO {
    private String machineReference;  // Format: W(workshop)-C(chain)-M(machine)
    private int timeTaken;
    private String description;
    private String date;
    
    // Constructors
    public MachineFailureDTO() {}
    
    public MachineFailureDTO(String machineReference, int timeTaken, 
                         String description, String date) {
        this.machineReference = machineReference;
        this.timeTaken = timeTaken;
        this.description = description;
        this.date = date;
    }
    
    // Getters and Setters
    public String getMachineReference() {
        return machineReference;
    }
    
    public void setMachineReference(String machineReference) {
        this.machineReference = machineReference;
    }
    
    public int getTimeTaken() {
        return timeTaken;
    }
    
    public void setTimeTaken(int timeTaken) {
        this.timeTaken = timeTaken;
    }
    
    public String getDescription() {
        return description;
    }
    
    public void setDescription(String description) {
        this.description = description;
    }
    
    public String getDate() {
        return date;
    }
    
    public void setDate(String date) {
        this.date = date;
    }
} 