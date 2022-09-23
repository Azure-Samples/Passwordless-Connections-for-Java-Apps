package com.azure.samples.repository;


import static jakarta.transaction.Transactional.TxType.REQUIRED;
import static jakarta.transaction.Transactional.TxType.SUPPORTS;

import java.util.List;
import java.util.Optional;


import com.azure.samples.model.CheckItem;

import jakarta.inject.Named;
import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;
import jakarta.persistence.Persistence;
import jakarta.transaction.Transactional;


@Named
@Transactional(REQUIRED)
public class CheckItemRepository {
	private EntityManagerFactory emf = Persistence.createEntityManagerFactory("PasswordlessDataSourcePU");
	private EntityManager em;

	public CheckItemRepository(){
		 
		em = emf.createEntityManager();
	}

	public CheckItem save(CheckItem item) {
		em.getTransaction().begin();
		em.persist(item);
		em.getTransaction().commit();
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
		em.getTransaction().begin();
		item = em.merge(item);
		em.getTransaction().commit();
		return item;		
	}

	public void deleteById(Long id) {
		em.getTransaction().begin();
		em.remove(em.find(CheckItem.class, id));
		em.getTransaction().commit();
	}
}
