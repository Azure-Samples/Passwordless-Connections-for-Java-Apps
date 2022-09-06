package com.microsoft.azure.samples.springcredentialfree.service;

import java.util.List;
import java.util.Optional;

import com.microsoft.azure.samples.springcredentialfree.model.CheckItem;
import com.microsoft.azure.samples.springcredentialfree.model.Checklist;

public interface CheckListService {
    
    Optional<Checklist> findById(Long id);
    
    void deleteById(Long id);

    List<Checklist> findAll();

    Checklist save(Checklist checklist);

    CheckItem addCheckItem(Long checklistId, CheckItem checkItem);
}
