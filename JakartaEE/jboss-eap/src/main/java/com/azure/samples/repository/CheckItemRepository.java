package com.azure.samples.repository;


import java.util.List;
import java.util.Optional;

import javax.enterprise.context.RequestScoped;
import javax.persistence.EntityManager;
import javax.persistence.PersistenceContext;
import javax.transaction.Transactional;

import com.azure.samples.model.CheckItem;

import static javax.transaction.Transactional.TxType.REQUIRED;
import static javax.transaction.Transactional.TxType.SUPPORTS;


@RequestScoped
@Transactional(REQUIRED)
public class CheckItemRepository {
	@PersistenceContext(unitName = "CredentialFreeDataSourcePU")
	private EntityManager em;

	public CheckItem save(CheckItem item) {
		em.persist(item);
		return item;
	}
	
	@Transactional(SUPPORTS)
	public Optional<CheckItem> findById(Long id) {
		
		CheckItem item = em.find(CheckItem.class, id);
		return item != null ? Optional.of(item) : Optional.empty();
	}

	@Transactional(SUPPORTS)
	public List<CheckItem> findAll() {
		return em.createQuery("CheckItem.findAll", CheckItem.class).getResultList();
	}

	public CheckItem update(CheckItem item) {
		item = em.merge(item);
		return item;
	}

	public void deleteById(Long id) {
		em.remove(em.find(CheckItem.class, id));
	}
}
