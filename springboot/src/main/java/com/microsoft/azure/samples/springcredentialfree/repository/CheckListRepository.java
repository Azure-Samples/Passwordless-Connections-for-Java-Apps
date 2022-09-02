package com.microsoft.azure.samples.springcredentialfree.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import com.microsoft.azure.samples.springcredentialfree.model.Checklist;

public interface CheckListRepository extends JpaRepository<Checklist, Long> {
}
