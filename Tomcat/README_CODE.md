# Overview of the code

In this project, we will access to Postgres DB from a Tomcat 10 Rest API..
To connect to the Postgres from Java, you need implement and configure the project with following procedure.

1. Add dependency for Postgres JDBC driver
2. Add dependency for JDBC Passwordless authentication plugin
3. Create a DataSource in Context.xml.
4. Configure web.xml to reference the server data source
5. Create a persistence unit config for JPA on persistence.xml
6. Create EntityManager Instance from EntityManagerFactory
7. Implement JAX-RS Endpoint
8. Access to the RESTful Endpoint

## 1. Add dependency for Postgress JDBC driver

A dependency for Postgres JDBC driver as follows on `pom.xml`. If Postgres provide a new version of the JDBC driver, please change the version number.

```xml
<dependency>
    <groupId>org.postgresql</groupId>
    <artifactId>postgresql</artifactId>
    <version>42.5.0</version>
</dependency>
```

## 2. Add dependency for JDBC Passwordless Authentication plugin

```xml
<dependency>
    <groupId>com.azure</groupId>
    <artifactId>azure-identity-providers-jdbc-postgresql</artifactId>
    <version>1.0.0-beta.1</version>
</dependency>
```

## 3. Create a DataSource in Context.xml

In order to create a DataSource, you need to create a DataSource on your Application Server. To create a DataSource, you need to create a `Context.xml` file on `src/main/webapp/META-INF` directory.

```xml
<Context>
    <Resource name="jdbc/passwordless" 
        auth="Container" 
        type="javax.sql.DataSource"
        driverClassName="org.postgresql.Driver"
        url="${dbUrl}"
        defaultAutoCommit="true"
        maxTotal="20"
        maxIdle="10"
        maxWaitMillis="-1"/>
</Context>
```

As you can see, there is ${dbUrl} parameter. It should be passed as an environment variable during Tomcat startup, as explained [here](README.md#deploy-the-application).

## 4. Configure web.xml to reference the server data source

To make the server data source available to the application is necessary to reference it on the web.xml file.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<web-app version="5.0" xmlns="https://jakarta.ee/xml/ns/jakartaee" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="https://jakarta.ee/xml/ns/jakartaee https://jakarta.ee/xml/ns/jakartaee/web-app_5_0.xsd">
    <resource-env-ref>
        <resource-env-ref-name>BeanManager</resource-env-ref-name>
        <resource-env-ref-type>
                    jakarta.enterprise.inject.spi.BeanManager
                </resource-env-ref-type>
    </resource-env-ref>
    <resource-ref>
        <description>postgreSQL Datasource example</description>
        <res-ref-name>jdbc/passwordless</res-ref-name>
        <res-type>javax.sql.DataSource</res-type>
        <res-auth>Container</res-auth>
    </resource-ref>
</web-app>
```

## 5. Create a persistence unit config for JPA on persistence.xml

After created the DataSource, you need create persistence unit config on [persistence.xml](src/main/resources/META-INF/persistence.xml) which is the configuration file of JPA.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<persistence version="2.2" xmlns="http://xmlns.jcp.org/xml/ns/persistence" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://xmlns.jcp.org/xml/ns/persistence http://xmlns.jcp.org/xml/ns/persistence/persistence_2_2.xsd">
  <persistence-unit name="PasswordlessDataSourcePU" transaction-type="RESOURCE_LOCAL">
    <non-jta-data-source>java:comp/env/jdbc/passwordless</non-jta-data-source>
    <properties>
      <property name="hibernate.dialect" value="org.hibernate.dialect.PostgreSQLDialect" />
      <property name="jakarta.persistence.schema-generation.database.action" value="create" />
    </properties>
  </persistence-unit>
</persistence>
```

## 6. Create EntityManager Instance from EntityManagerFactory

Then you can create an EntityManagerFactory using the the persistence unit.  
In the `CheckListRepository.java` and `CheckItemRepository.java` code, you can see the how the EntityManagerFactory is created using the persistence unit.

Following is [CheckListRepository.java](src/main/java/com/azure/samples/repository/CheckListRepository.java) code.

```java
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

    public Optional<Checklist> findById(Long id) {
        Checklist checklist = em.find(Checklist.class, id);
        return checklist != null ? Optional.of(checklist) : Optional.empty();
    }

    public List<Checklist> findAll() {
        return em.createNamedQuery("Checklist.findAll", Checklist.class).getResultList();
    }

    public void deleteById(Long id) {
        em.getTransaction().begin();
        em.remove(em.find(Checklist.class, id));
        em.getTransaction().commit();
    }
}
```

## 7. Implement JAX-RS resource

Finally, you can implement the JAX-RS resource in [CheckListResource.java](src/main/java/com/azure/samples/controller/CheckListResource.java) by injecting the `CheckListService` which implemented in the above.  
And we configured to use the JSON-B in this project, so it automatically marshall the JSON data from Java object. As a result, it return the JSON data in the response.

```java

@Path("/checklist")
public class CheckListResource {

    @Inject
    private CheckListService checkListService;

 
    @GET
 @Produces(MediaType.APPLICATION_JSON)
 public List<Checklist> getCheckLists() {  
  return checkListService.findAll();
 }

    @GET
 @Path("{checklistId}")
 @Produces(MediaType.APPLICATION_JSON)
 public Checklist getCheckList(@PathParam(value = "checklistId") Long checklistId) {
  return checkListService.findById(checklistId).orElseThrow(() -> new ResourceNotFoundException("checklist  " + checklistId + " not found"));
 }

    @POST
    @Produces(MediaType.APPLICATION_JSON)
    public Checklist createCheckList(@Valid Checklist checklist) {
        return checkListService.save(checklist);
    }

    @POST
    @Path("{checklistId}/item")
    @Produces(MediaType.APPLICATION_JSON)
    public CheckItem addCheckItem(@PathParam(value = "checklistId") Long checklistId, @Valid CheckItem checkItem) {
        return checkListService.addCheckItem(checklistId, checkItem);
    }
}
```

## 8. Access to the RESTful Endpoint

The checklist resource is exposed in _/checklist_ path. So you can test it by executing the following command.

```bash
curl https://[yourwebapp].azurewebsites.net/checklist
[{"date":"2022-03-21T00:00:00","description":"oekd list","id":1,"name":"hajshd"},{"date":"2022-03-21T00:00:00","description":"oekd list","id":2,"name":"hajshd"},{"date":"2022-03-21T00:00:00","description":"oekd list","id":3,"name":"hajshd"}]
```

As part of this sample, it is provided a [postman collection](postman/check_lists_request.postman_collection.json) which you can use to test the RESTful API. Just change _appUrl_ variable by your Azure App Service URL.
