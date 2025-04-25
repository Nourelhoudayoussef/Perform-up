package com.example.pfeBack.dto;

public class DailyTargetRequestDTO {
    private Integer orderRef;
    private int targetQuantity;
    private String date;
    
    // Constructors
    public DailyTargetRequestDTO() {}
    
    public DailyTargetRequestDTO(Integer orderRef, int targetQuantity, String date) {
        this.orderRef = orderRef;
        this.targetQuantity = targetQuantity;
        this.date = date;
    }
    
    // Getters and Setters
    public Integer getOrderRef() {
        return orderRef;
    }
    
    public void setOrderRef(Integer orderRef) {
        this.orderRef = orderRef;
    }
    
    public int getTargetQuantity() {
        return targetQuantity;
    }
    
    public void setTargetQuantity(int targetQuantity) {
        this.targetQuantity = targetQuantity;
    }
    
    public String getDate() {
        return date;
    }
    
    public void setDate(String date) {
        this.date = date;
    }
} 