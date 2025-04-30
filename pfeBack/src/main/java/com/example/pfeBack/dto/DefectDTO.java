package com.example.pfeBack.dto;

/**
 * DTO for defect information
 */
public class DefectDTO {
    private String defectType;
    private int count;
    
    // Constructors
    public DefectDTO() {}
    
    public DefectDTO(String defectType, int count) {
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