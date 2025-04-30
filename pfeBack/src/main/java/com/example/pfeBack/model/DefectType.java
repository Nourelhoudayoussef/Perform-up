package com.example.pfeBack.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "defect_types")
public class DefectType {
    @Id
    private String id;
    private int defectTypes;
    private String defectName;
    
    // Constructors
    public DefectType() {}
    
    public DefectType(int defectTypes, String defectName) {
        this.defectTypes = defectTypes;
        this.defectName = defectName;
    }
    
    // Getters and Setters
    public String getId() {
        return id;
    }
    
    public void setId(String id) {
        this.id = id;
    }
    
    public int getDefectTypes() {
        return defectTypes;
    }
    
    public void setDefectTypes(int defectTypes) {
        this.defectTypes = defectTypes;
    }
    
    public String getDefectName() {
        return defectName;
    }
    
    public void setDefectName(String defectName) {
        this.defectName = defectName;
    }
} 