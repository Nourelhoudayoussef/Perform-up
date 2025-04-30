package com.example.pfeBack.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "monthly_performance")
public class MonthlyPerformance {
    @Id
    private String id;
    private String month;
    private String orderRef;
    private int productionTarget;
    private int produced;
    private int defects;
    
    // Constructors
    public MonthlyPerformance() {}
    
    public MonthlyPerformance(String month, String orderRef, int productionTarget, int produced, int defects) {
        this.month = month;
        this.orderRef = orderRef;
        this.productionTarget = productionTarget;
        this.produced = produced;
        this.defects = defects;
    }
    
    // Getters and Setters
    public String getId() {
        return id;
    }
    
    public void setId(String id) {
        this.id = id;
    }
    
    public String getMonth() {
        return month;
    }
    
    public void setMonth(String month) {
        this.month = month;
    }
    
    public String getOrderRef() {
        return orderRef;
    }
    
    public void setOrderRef(String orderRef) {
        this.orderRef = orderRef;
    }
    
    public int getProductionTarget() {
        return productionTarget;
    }
    
    public void setProductionTarget(int productionTarget) {
        this.productionTarget = productionTarget;
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
} 