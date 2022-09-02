package com.azure.samples.model;

import javax.json.bind.annotation.JsonbTransient;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.NamedQueries;
import javax.persistence.NamedQuery;
import javax.persistence.Table;

@Entity
@Table(name="checkitem")
@NamedQueries({ @NamedQuery(name = "CheckItem.findAll", query = "SELECT c FROM CheckItem c") })
public class CheckItem {
    
    @Id
    @Column(name="ID")
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @JoinColumn(name="checklist_ID")
    @ManyToOne  
    @JsonbTransient  
    private Checklist checklist;

    @Column(name="description")
    private String description;

    public Long getId() {
        return id;
    }

    public void setId(final Long id) {
        this.id = id;
    }

    public Checklist getCheckList() {
        return checklist;
    }

    public void setCheckList(Checklist checklist) {
        this.checklist = checklist;
    }

    
    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }   
    
}
