package com.example.pfeBack.model;

/**
 * Represents a specific defect with its type and count
 */
public class Defect {
    private String defectType;
    private int count;
    
    // Constructors
    public Defect() {}
    
    public Defect(String defectType, int count) {
        this.defectType = defectType;
        this.count = count;
    }
    
    // Getters and Setters
    public String getDefectType() {
        return defectType;
    }
    
    public void setDefectType(String defectType) {
        this.defectType = defectType;
    }
    
    public int getCount() {
        return count;
    }
    
    public void setCount(int count) {
        this.count = count;
    }
} 