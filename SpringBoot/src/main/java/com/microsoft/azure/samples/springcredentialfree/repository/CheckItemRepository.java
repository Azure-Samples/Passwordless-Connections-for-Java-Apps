package com.microsoft.azure.samples.springcredentialfree.repository;

import org.springframework.data.jpa.repository.JpaRepository;

import com.microsoft.azure.samples.springcredentialfree.model.CheckItem;

public interface CheckItemRepository extends JpaRepository<CheckItem, Long> {
}
