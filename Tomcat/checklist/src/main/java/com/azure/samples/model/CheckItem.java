package com.azure.samples.model;

import com.fasterxml.jackson.annotation.JsonIgnore;

import jakarta.json.bind.annotation.JsonbTransient;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.NamedQueries;
import jakarta.persistence.NamedQuery;
import jakarta.persistence.Table;

@Entity
@Table(name = "checkitem")
@NamedQueries({ @NamedQuery(name = "CheckItem.findAll", query = "SELECT c FROM CheckItem c") })
public class CheckItem {

    @Id
    @Column(name = "ID")
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @JoinColumn(name = "checklist_ID")
    @ManyToOne(fetch = FetchType.LAZY)
    @JsonbTransient
    private Checklist checklist;

    @Column(name = "description")
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
