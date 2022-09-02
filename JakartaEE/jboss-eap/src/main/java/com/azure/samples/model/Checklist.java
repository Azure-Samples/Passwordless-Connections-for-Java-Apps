package com.azure.samples.model;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import javax.json.bind.annotation.JsonbDateFormat;
import javax.json.bind.annotation.JsonbTransient;
import javax.persistence.CascadeType;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import javax.persistence.NamedQueries;
import javax.persistence.NamedQuery;
import javax.persistence.OneToMany;
import javax.persistence.Table;
import javax.persistence.Temporal;
import javax.persistence.TemporalType;

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
    // @NotEmpty
    @JsonbDateFormat("yyyy-MM-dd'T'HH:mm:ss")
    private Date date;

    @Column(name = "description")
    private String description;

    @JsonbTransient
    @OneToMany(cascade = CascadeType.ALL, fetch = FetchType.LAZY, mappedBy = "checklist")
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
