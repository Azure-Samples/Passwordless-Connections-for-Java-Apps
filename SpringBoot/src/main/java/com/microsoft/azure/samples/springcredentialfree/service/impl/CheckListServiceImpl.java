package com.microsoft.azure.samples.springcredentialfree.service.impl;

import java.util.List;
import java.util.Optional;

import org.springframework.stereotype.Service;

import com.microsoft.azure.samples.springcredentialfree.exception.ResourceNotFoundException;
import com.microsoft.azure.samples.springcredentialfree.model.CheckItem;
import com.microsoft.azure.samples.springcredentialfree.model.Checklist;
import com.microsoft.azure.samples.springcredentialfree.repository.CheckItemRepository;
import com.microsoft.azure.samples.springcredentialfree.repository.CheckListRepository;
import com.microsoft.azure.samples.springcredentialfree.service.CheckListService;



@Service
public class CheckListServiceImpl implements CheckListService {
    
    private final CheckListRepository checkListRepository;
    
    private final CheckItemRepository checkItemRepository;

    public CheckListServiceImpl(CheckListRepository checkListRepository, CheckItemRepository checkItemRepository) {
        this.checkListRepository = checkListRepository;
        this.checkItemRepository = checkItemRepository;
    }

    @Override
    public Optional<Checklist> findById(Long id) {
        return checkListRepository.findById(id);
    }

    @Override
    public void deleteById(Long id) {
        checkListRepository.deleteById(id);

    }

    @Override
    public List<Checklist> findAll() {
        return checkListRepository.findAll();
    }

    @Override
    public Checklist save(Checklist checklist) {
        return checkListRepository.save(checklist);
    }

    @Override
    public CheckItem addCheckItem(Long checklistId, CheckItem checkItem) {
        Checklist checkList = checkListRepository.findById(checklistId)
                .orElseThrow(() -> new ResourceNotFoundException("Checklist " + checklistId + " not found"));
        checkItem.setCheckList(checkList);
        return checkItemRepository.save(checkItem);
    }
}
