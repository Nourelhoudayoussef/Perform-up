package com.example.pfeBack.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import java.util.Date;

@Document(collection = "defect_data")
public class DefectData {
    @Id
    private String id;
    private Date timestamp;  
    private int chainNumber;
    private int workshopNumber;
    private String defectType; 
    private int defectCount;

    // Constructors
    public DefectData() {}

    public DefectData(Date timestamp, int chainNumber, int workshopNumber, String defectType, int defectCount) {
        this.timestamp = timestamp;
        this.chainNumber = chainNumber;
        this.workshopNumber = workshopNumber;
        this.defectType = defectType;
        this.defectCount = defectCount;
    }

    // Getters & Setters
    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public Date getTimestamp() { return timestamp; }
    public void setTimestamp(Date timestamp) { this.timestamp = timestamp; }

    public int getChainNumber() { return chainNumber; }
    public void setChainNumber(int chainNumber) { this.chainNumber = chainNumber; }

    public int getWorkshopNumber() { return workshopNumber; }
    public void setWorkshopNumber(int workshopNumber) { this.workshopNumber = workshopNumber; }

    public String getDefectType() { return defectType; }
    public void setDefectType(String defectType) { this.defectType = defectType; }

    public int getDefectCount() { return defectCount; }
    public void setDefectCount(int defectCount) { this.defectCount = defectCount; }
}

