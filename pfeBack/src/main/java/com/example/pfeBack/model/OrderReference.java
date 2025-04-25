package com.example.pfeBack.model;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.mapping.Document;

@Document(collection = "order_references")
public class OrderReference {
    @Id
    private String id;
    private Integer orderRef;
    private String productName;
    
    // Constructors
    public OrderReference() {}
    
    public OrderReference(Integer orderRef, String productName) {
        this.orderRef = orderRef;
        this.productName = productName;
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
    
    public String getProductName() {
        return productName;
    }
    
    public void setProductName(String productName) {
        this.productName = productName;
    }
} 