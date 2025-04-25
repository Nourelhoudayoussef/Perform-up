package com.example.pfeBack.model;

import com.fasterxml.jackson.annotation.JsonIgnore;
import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import java.util.ArrayList;
import java.util.List;

@Document(collection = "performance3")
public class Performance {
    @Id
    private String id;
    private String supervisorId;
    private String date;
    private String hour;
    private String workshop;
    private String chain;
    private int produced;
    
    @JsonIgnore // Hide this field from JSON responses
    private int defects; // Total count of all defects (for backward compatibility)
    
    @JsonIgnore // Hide this field from JSON responses
    private String defectName; // For backward compatibility
    
    private List<Defect> defectList = new ArrayList<>(); // New field for multiple defect types
    private int productionTarget;
    private Integer orderRef;
    
    // Constructors
    public Performance() {}
    
    public Performance(String supervisorId, String date, String hour, String workshop, 
                      String chain, int produced, int defects, String defectName, 
                      int productionTarget, Integer orderRef) {
        this.supervisorId = supervisorId;
        this.date = date;
        this.hour = hour;
        this.workshop = workshop;
        this.chain = chain;
        this.produced = produced;
        this.defects = defects;
        this.defectName = defectName;
        this.productionTarget = productionTarget;
        this.orderRef = orderRef;
        
        // Initialize defectList with a single defect if provided
        if (defects > 0 && defectName != null && !defectName.isEmpty()) {
            this.defectList.add(new Defect(defectName, defects));
        }
    }

    // New constructor with defect list
    public Performance(String supervisorId, String date, String hour, String workshop, 
                      String chain, int produced, List<Defect> defectList,
                      int productionTarget, Integer orderRef) {
        this.supervisorId = supervisorId;
        this.date = date;
        this.hour = hour;
        this.workshop = workshop;
        this.chain = chain;
        this.produced = produced;
        this.defectList = defectList;
        
        // Calculate total defects for backward compatibility
        this.defects = defectList.stream().mapToInt(Defect::getCount).sum();
        
        // Use first defect type for backward compatibility if available
        if (!defectList.isEmpty()) {
            this.defectName = defectList.get(0).getDefectType();
        } else {
            this.defectName = "";
        }
        
        this.productionTarget = productionTarget;
        this.orderRef = orderRef;
    }
    
    // Getters and Setters
    public String getId() {
        return id;
    }
    
    public void setId(String id) {
        this.id = id;
    }
    
    public String getSupervisorId() {
        return supervisorId;
    }
    
    public void setSupervisorId(String supervisorId) {
        this.supervisorId = supervisorId;
    }
    
    public String getDate() {
        return date;
    }
    
    public void setDate(String date) {
        this.date = date;
    }
    
    public String getHour() {
        return hour;
    }
    
    public void setHour(String hour) {
        this.hour = hour;
    }
    
    public String getWorkshop() {
        return workshop;
    }
    
    public void setWorkshop(String workshop) {
        this.workshop = workshop;
    }
    
    public String getChain() {
        return chain;
    }
    
    public void setChain(String chain) {
        this.chain = chain;
    }
    
    public int getProduced() {
        return produced;
    }
    
    public void setProduced(int produced) {
        this.produced = produced;
    }
    
    public int getDefects() {
        return defects;
    }
    
    public void setDefects(int defects) {
        this.defects = defects;
    }
    
    public String getDefectName() {
        return defectName;
    }
    
    public void setDefectName(String defectName) {
        this.defectName = defectName;
    }
    
    public List<Defect> getDefectList() {
        return defectList;
    }
    
    public void setDefectList(List<Defect> defectList) {
        this.defectList = defectList;
        
        // Update backward compatibility fields
        this.defects = defectList.stream().mapToInt(Defect::getCount).sum();
        if (!defectList.isEmpty()) {
            this.defectName = defectList.get(0).getDefectType();
        } else {
            this.defectName = "";
        }
    }
    
    // Helper method to add a single defect
    public void addDefect(Defect defect) {
        if (this.defectList == null) {
            this.defectList = new ArrayList<>();
        }
        this.defectList.add(defect);
        
        // Update backward compatibility fields
        this.defects = this.defectList.stream().mapToInt(Defect::getCount).sum();
    }
    
    public int getProductionTarget() {
        return productionTarget;
    }
    
    public void setProductionTarget(int productionTarget) {
        this.productionTarget = productionTarget;
    }
    
    public Integer getOrderRef() {
        return orderRef;
    }
    
    public void setOrderRef(Integer orderRef) {
        this.orderRef = orderRef;
    }
} 