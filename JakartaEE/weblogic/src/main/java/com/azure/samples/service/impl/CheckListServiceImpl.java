package com.azure.samples.service.impl;

import java.util.List;
import java.util.Optional;

import com.azure.samples.exception.ResourceNotFoundException;
import com.azure.samples.model.CheckItem;
import com.azure.samples.model.Checklist;
import com.azure.samples.repository.CheckItemRepository;
import com.azure.samples.repository.CheckListRepository;
import com.azure.samples.service.CheckListService;

import javax.inject.Inject;
import javax.inject.Named;
import javax.validation.Valid;

@Named
public class CheckListServiceImpl implements CheckListService {

    @Inject
    CheckListRepository checkListRepository;
    @Inject
    CheckItemRepository checkItemRepository;

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
    public CheckItem addCheckItem(Long checklistId, @Valid CheckItem checkItem) {
        Checklist checkList = checkListRepository.findById(checklistId)
                .orElseThrow(() -> new ResourceNotFoundException("Checklist " + checklistId + " not found"));
        checkItem.setCheckList(checkList);
        return checkItemRepository.save(checkItem);
    }
}
