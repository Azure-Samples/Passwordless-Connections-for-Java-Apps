package com.microsoft.azure.samples.springcredentialfree.web;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

import org.springframework.http.HttpStatus;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import com.microsoft.azure.samples.springcredentialfree.exception.ResourceNotFoundException;
import com.microsoft.azure.samples.springcredentialfree.model.CheckItem;
import com.microsoft.azure.samples.springcredentialfree.model.Checklist;
import com.microsoft.azure.samples.springcredentialfree.service.CheckListService;

@RequestMapping("/checklist")
@RestController
public class ChecklistResource {
    private final CheckListService checkListService;

    public ChecklistResource(CheckListService checklistService) {
        this.checkListService = checklistService;

    }

    @GetMapping
    public List<Checklist> getCheckLists() {
        return checkListService.findAll();
    }

    @GetMapping("{checklistId}")
    public Checklist getCheckList(@PathVariable(value = "checklistId") Long checklistId) {
        return checkListService.findById(checklistId)
                .orElseThrow(() -> new ResourceNotFoundException("checklist  " + checklistId + " not found"));
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public Checklist createCheckList(@RequestBody Checklist checklist) {
        return checkListService.save(checklist);
    }

    @PostMapping("{checklistId}/item")
    @ResponseStatus(HttpStatus.CREATED)
    public CheckItem addCheckItem(@PathVariable(value = "checklistId") Long checklistId,
            @RequestBody CheckItem checkItem) {
        return checkListService.addCheckItem(checklistId, checkItem);
    }

}
