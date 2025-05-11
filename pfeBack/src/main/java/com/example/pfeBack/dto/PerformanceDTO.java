package com.example.pfeBack.dto;

import java.util.ArrayList;
import java.util.List;

public class PerformanceDTO {
    private Integer orderRef;
    private int produced;
    private int defects; // For backward compatibility with existing database records
    private String defectName; // For backward compatibility with existing database records
    private List<DefectDTO> defectList = new ArrayList<>(); // List of defects
    private String hour;
    private String date; // Optional - will be set automatically to current date
    private int workshopInt;
    private int chainInt;
    
    // Constructors
    public PerformanceDTO() {}
    
    public PerformanceDTO(Integer orderRef, int produced, List<DefectDTO> defectList, String hour, String date, int workshopInt, int chainInt) {
        this.orderRef = orderRef;
        this.produced = produced;
        this.defectList = defectList;
        this.hour = hour;
        this.date = date;
        this.workshopInt = workshopInt;
        this.chainInt = chainInt;
        this.defects = defectList.stream().mapToInt(DefectDTO::getCount).sum();
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
    
    public int getWorkshopInt() {
        return workshopInt;
    }
    
    public void setWorkshopInt(int workshopInt) {
        this.workshopInt = workshopInt;
    }
    
    public int getChainInt() {
        return chainInt;
    }
    
    public void setChainInt(int chainInt) {
        this.chainInt = chainInt;
    }
} 