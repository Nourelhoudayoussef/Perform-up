package com.example.pfeBack.dto;

import java.util.ArrayList;
import java.util.List;

public class PerformanceDTO {
    private Integer orderRef;
    private String workshop;
    private String chain;
    private int produced;
    private int defects; // For backward compatibility with existing database records
    private String defectName; // For backward compatibility with existing database records
    private List<DefectDTO> defectList = new ArrayList<>(); // List of defects
    private String hour;
    private String date; // Optional - will be set automatically to current date
    private int productionTarget;
    
    // Constructors
    public PerformanceDTO() {}
    
    // Constructor with defect list
    public PerformanceDTO(Integer orderRef, String workshop, String chain,
                        int produced, List<DefectDTO> defectList, 
                        String hour, String date, int productionTarget) {
        this.orderRef = orderRef;
        this.workshop = workshop;
        this.chain = chain;
        this.produced = produced;
        this.defectList = defectList;
        this.hour = hour;
        this.date = date;
        this.productionTarget = productionTarget;
        
        // Calculate total defects for backward compatibility
        this.defects = defectList.stream().mapToInt(DefectDTO::getCount).sum();
        
        // Use first defect type for backward compatibility if available
        if (!defectList.isEmpty()) {
            this.defectName = defectList.get(0).getDefectType();
        } else {
            this.defectName = "";
        }
    }
    
    // Getters and Setters
    public Integer getOrderRef() {
        return orderRef;
    }
    
    public void setOrderRef(Integer orderRef) {
        this.orderRef = orderRef;
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
    
    public List<DefectDTO> getDefectList() {
        return defectList;
    }
    
    public void setDefectList(List<DefectDTO> defectList) {
        this.defectList = defectList;
        
        // Update backward compatibility fields
        this.defects = defectList.stream().mapToInt(DefectDTO::getCount).sum();
        if (!defectList.isEmpty()) {
            this.defectName = defectList.get(0).getDefectType();
        } else {
            this.defectName = "";
        }
    }
    
    public String getHour() {
        return hour;
    }
    
    public void setHour(String hour) {
        this.hour = hour;
    }
    
    public String getDate() {
        return date;
    }
    
    public void setDate(String date) {
        this.date = date;
    }
    
    public int getProductionTarget() {
        return productionTarget;
    }
    
    public void setProductionTarget(int productionTarget) {
        this.productionTarget = productionTarget;
    }
} 