package com.azure.samples.service;

import java.util.List;
import java.util.Optional;

import com.azure.samples.model.CheckItem;
import com.azure.samples.model.Checklist;

import javax.validation.Valid;

public interface CheckListService {
    
    Optional<Checklist> findById(Long id);
    
    void deleteById(Long id);

    List<Checklist> findAll();

    Checklist save(Checklist checklist);

    CheckItem addCheckItem(Long checklistId, @Valid CheckItem checkItem);
}
