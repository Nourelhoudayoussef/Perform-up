package com.example.pfeBack.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import org.springframework.data.mongodb.core.mapping.Field;

@Document(collection = "new_data.machinefailures")
public class MachineFailure {
    @Id
    private String id;
    private String date;
    private int timeSpent; // Consolidated field for time spent on intervention
    
    @Field("technician_id")
    private String technician_id;
    
    @Field("technician_name")
    private String technician_name;
    
    private String machineReference; // Format: W(workshop)-C(chain)-M(machine)
    private String description;
    
    // Constructors
    public MachineFailure() {}
    
    public MachineFailure(String date, int timeSpent, String technician_id, String technician_name,
                         String machineReference, String description) {
        this.date = date;
        this.timeSpent = timeSpent;
        this.technician_id = technician_id;
        this.technician_name = technician_name;
        this.machineReference = machineReference;
        this.description = description;
    }
    
    // Getters and Setters
    public String getId() {
        return id;
    }
    
    public void setId(String id) {
        this.id = id;
    }
    
    public String getDate() {
        return date;
    }
    
    public void setDate(String date) {
        this.date = date;
    }
    
    public int getTimeSpent() {
        return timeSpent;
    }
    
    public void setTimeSpent(int timeSpent) {
        this.timeSpent = timeSpent;
    }

    public String getMachineReference() {
        return machineReference;
    }
    
    public void setMachineReference(String machineReference) {
        this.machineReference = machineReference;
    }
    
    public String getDescription() {
        return description;
    }
    
    public void setDescription(String description) {
        this.description = description;
    }
    
    // For backward compatibility with existing code
    public int getTime_spent() {
        return timeSpent;
    }
    
    public void setTime_spent(int time_spent) {
        this.timeSpent = time_spent;
    }
    
    public String getTechnician_id() {
        return technician_id;
    }
    
    public void setTechnician_id(String technician_id) {
        this.technician_id = technician_id;
    }
    
    public String getTechnician_name() {
        return technician_name;
    }
    
    public void setTechnician_name(String technician_name) {
        this.technician_name = technician_name;
    }
} 