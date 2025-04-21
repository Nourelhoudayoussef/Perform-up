package com.example.pfeBack.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;
import java.util.Date;

@Document(collection = "production_data")
public class ProductionData {
    @Id
    private String id;
    private Date timestamp; 
    private int quantity;  
    private String size;
    private String color;
    private int chainNumber;
    private int workshopNumber;

    // Constructors
    public ProductionData() {}

    public ProductionData(Date timestamp, int quantity, String size, String color, int chainNumber, int workshopNumber) {
        this.timestamp = timestamp;
        this.quantity = quantity;
        this.size = size;
        this.color = color;
        this.chainNumber = chainNumber;
        this.workshopNumber = workshopNumber;
    }

    // Getters & Setters
    public String getId() { return id; }
    public void setId(String id) { this.id = id; }

    public Date getTimestamp() { return timestamp; }
    public void setTimestamp(Date timestamp) { this.timestamp = timestamp; }

    public int getQuantity() { return quantity; }
    public void setQuantity(int quantity) { this.quantity = quantity; }

    public String getSize() { return size; }
    public void setSize(String size) { this.size = size; }

    public String getColor() { return color; }
    public void setColor(String color) { this.color = color; }

    public int getChainNumber() { return chainNumber; }
    public void setChainNumber(int chainNumber) { this.chainNumber = chainNumber; }

    public int getWorkshopNumber() { return workshopNumber; }
    public void setWorkshopNumber(int workshopNumber) { this.workshopNumber = workshopNumber; }
}
