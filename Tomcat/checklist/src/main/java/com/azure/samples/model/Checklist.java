package com.azure.samples.model;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import com.fasterxml.jackson.annotation.JsonFormat;

import jakarta.json.bind.annotation.JsonbTransient;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.NamedQueries;
import jakarta.persistence.NamedQuery;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import jakarta.persistence.Temporal;
import jakarta.persistence.TemporalType;

@Entity
@Table(name = "checklist")
@NamedQueries({ @NamedQuery(name = "Checklist.findAll", query = "SELECT c FROM Checklist c") })
public class Checklist {

    @Id
    @Column(name = "ID")
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "name")
    // @NotEmpty
    private String name;

    @Column(name = "date")
    @Temporal(TemporalType.DATE)
    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd@HH:mm:ssZ")
    private Date date;

    @Column(name = "description")
    private String description;

    @JsonbTransient
    @OneToMany(cascade = CascadeType.ALL, fetch = FetchType.EAGER, mappedBy = "checklist")
    private Set<CheckItem> items;

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public Date getDate() {
        return date;
    }

    public void setDate(Date date) {
        this.date = date;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    protected Set<CheckItem> getCheckItemsInternal() {
        if (this.items == null) {
            this.items = new HashSet<>();
        }
        return this.items;
    }

    public List<CheckItem> getItems() {
        return Collections.unmodifiableList(new ArrayList<>(getCheckItemsInternal()));
    }

    public void addItem(CheckItem item) {
        getCheckItemsInternal().add(item);
        item.setCheckList(this);
    }

}
