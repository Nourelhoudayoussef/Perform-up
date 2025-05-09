package com.example.pfeBack.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "order_references")
public class OrderReference {
    @Id
    private String id;
    private Integer orderRef;
    private Integer productionTarget;
    private String date;
    
    // Constructors
    public OrderReference() {}
    
    public OrderReference(Integer orderRef, Integer productionTarget, String date) {
        this.orderRef = orderRef;
        this.productionTarget = productionTarget;
        this.date = date;
    }
    
    // Getters and Setters
    public String getId() {
        return id;
    }
    
    public void setId(String id) {
        this.id = id;
    }
    
    public Integer getOrderRef() {
        return orderRef;
    }
    
    public void setOrderRef(Integer orderRef) {
        this.orderRef = orderRef;
    }
    
    public Integer getProductionTarget() {
        return productionTarget;
    }
    
    public void setProductionTarget(Integer productionTarget) {
        this.productionTarget = productionTarget;
    }
    
    public String getDate() {
        return date;
    }
    
    public void setDate(String date) {
        this.date = date;
    }
} 