package com.azure.samples.repository;

import static jakarta.transaction.Transactional.TxType.REQUIRED;
import static jakarta.transaction.Transactional.TxType.SUPPORTS;

import java.util.List;
import java.util.Optional;

import com.azure.samples.model.Checklist;

import jakarta.inject.Named;
import jakarta.persistence.EntityManager;
import jakarta.persistence.EntityManagerFactory;
import jakarta.persistence.Persistence;
import jakarta.transaction.Transactional;

@Transactional(REQUIRED)
@Named
public class CheckListRepository {

    private EntityManagerFactory emf = Persistence.createEntityManagerFactory("PasswordlessDataSourcePU");
    private EntityManager em;

    

    public CheckListRepository() {
        em = emf.createEntityManager();
    }

    public Checklist save(Checklist checklist) {
        em.getTransaction().begin();
        em.persist(checklist);
        em.getTransaction().commit();
        
        return checklist;
    }

    @Transactional(SUPPORTS)
    public Optional<Checklist> findById(Long id) {
        Checklist checklist = em.find(Checklist.class, id);
        return checklist != null ? Optional.of(checklist) : Optional.empty();
    }

    @Transactional(SUPPORTS)
    public List<Checklist> findAll() {
        return em.createNamedQuery("Checklist.findAll", Checklist.class).getResultList();
    }

    public void deleteById(Long id) {
        em.getTransaction().begin();
        em.remove(em.find(Checklist.class, id));
        em.getTransaction().commit();
    }
}
