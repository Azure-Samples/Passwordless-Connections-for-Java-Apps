# Overview of the code

In this project, we will access to MySQL DB from Jakarta EE 8 Application.
To connect to the MySQL from Java, you need implement and configure the project with following procedure.

1. Create and Configure as a Jakarta EE 8 Project
2. Add dependency for MySQL JDBC driver 
3. Add dependency for JDBC Credential-free authentication plugin
4. Create a DataSource with JNDI on your Application Server, with no password validation
5. Create a persistence unit config for JPA on persistence.xml
6. Inject EntityManager Instance
7. Configure for working with JAX-RS and JSON-B in JBoss EAP
8. Implement JAX-RS Endpoint
9. Access to the RESTful Endpoint

### 1. Create and Configure as a Jakarta EE 8 Project

In this project, we created Jakarta EE 8 projects. In order to create the Jakarta EE 8 project, we need specify following dependencies on [pom.xml](pom.xml).

```xml
    <jakarta.jakartaee-api.version>8.0.0</jakarta.jakartaee-api.version>
    ....
    <dependency>
      <groupId>jakarta.platform</groupId>
      <artifactId>jakarta.jakartaee-api</artifactId>
      <version>${jakarta.jakartaee-api.version}</version>
      <scope>provided</scope>
    </dependency>
```

### 2. Add dependency for MySQL JDBC driver 

we added a dependency for MySQL JDBC driver as follows on `pom.xml`. If MySQL provide a new version of the JDBC driver, please change the version number.

```xml
    <mysql-jdbc-driver>8.0.22</mysql-jdbc-driver>

    <dependency>
      <groupId>mysql</groupId>
      <artifactId>mysql-connector-java</artifactId>
      <version>${mysql-jdbc-driver}</version>
    </dependency>
```
### 3. Add dependency for JDBC Credential-free authentication plugin
```xml
<dependency>
      <groupId>com.azure</groupId>
      <artifactId>credential-free-jdbc</artifactId>
      <version>0.0.1-SNAPSHOT</version>
    </dependency>
```

### 4. Create a DataSource with JNDI on your Application Server with no password validation 

In order to create a DataSource, you need to create a DataSource on your Application Server.  
Following [createMySQLDataSource.sh](src/main/webapp/WEB-INF/createMySQLDataSource.sh) script create the DataSource on JBoss EAP with JBoss CLI command.

```bash
#!/bin/bash
# In order to use the variables in CLI scripts
# https://access.redhat.com/solutions/321513
sed -i -e "s|.*<resolve-parameter-values.*|<resolve-parameter-values>true</resolve-parameter-values>|g" /opt/eap/bin/jboss-cli.xml
/opt/eap/bin/jboss-cli.sh --connect <<EOF
data-source add --name=PasswordlessDataSourceDS \
--jndi-name=java:jboss/datasources/PasswordlessDataSource \
--connection-url=${MYSQL_CONNECTION_URL} \
--driver-name=ROOT.war_com.mysql.cj.jdbc.Driver_8_0 \
--user-name=${MYSQL_USER} \
--min-pool-size=5 \
--max-pool-size=20 \
--blocking-timeout-wait-millis=5000 \
--enabled=true \
--driver-class=com.mysql.cj.jdbc.Driver \
--jta=true \
--use-java-context=true \
--validate-on-match=false \
--background-validation=false \
--exception-sorter-class-name=com.mysql.cj.jdbc.integration.jboss.ExtendedMysqlExceptionSorter
exit
EOF
```
As you can see, there is no _password_ parameter and _validate-on-match_ and 
_background-validation_ are set to *false*. This is because we want to use the credential-free authentication plugin.

### 5. Create a persistence unit config for JPA on persistence.xml

After created the DataSource, you need create persistence unit config on [persistence.xml](src/main/resources/META-INF/persistence.xml) which is the configuration file of JPA.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<persistence version="2.2" xmlns="http://xmlns.jcp.org/xml/ns/persistence" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://xmlns.jcp.org/xml/ns/persistence http://xmlns.jcp.org/xml/ns/persistence/persistence_2_2.xsd">
  <persistence-unit name="PasswordlessDataSourcePU" transaction-type="JTA">
    <jta-data-source>java:jboss/datasources/PasswordlessDataSource</jta-data-source>
    <exclude-unlisted-classes>false</exclude-unlisted-classes>
    <properties>
      <property name="hibernate.generate_statistics" value="true" />
      <property name="hibernate.dialect" value="org.hibernate.dialect.MySQLDialect" />
    </properties>
  </persistence-unit>
</persistence>

```

### 6. Inject EntityManager Instance

Then you can inject an EntityManager instance from annotated unitName with `@PersistenceContext` like follows.  
In the `CheckListRepository.java` and `CheckItemRepository.java` code, you can see the injected  EntityManager instance with @PersistenceContext annotation.

Following is [CheckListRepository.java](src/main/java/com/azure/samples/repository/CheckListRepository.java) code.

```java
@Transactional(REQUIRED)
@RequestScoped
public class CheckListRepository {

    @PersistenceContext(unitName = "PasswordlessDataSourcePU")
    private EntityManager em;

    public Checklist save(Checklist checklist) {

        em.persist(checklist);
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
        em.remove(em.find(Checklist.class, id));
    }
}
```

### 7. Configure for working with JAX-RS and JSON-B in JBoss EAP

We will implement the standard Jakarta EE 8 API only, so in order to use the JSON-B with JAX-RS. we need configure the following parameter in [web.xml](src/main/webapp/WEB-INF/web.xml) for JBoss EAP App.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns="http://xmlns.jcp.org/xml/ns/javaee" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://xmlns.jcp.org/xml/ns/javaee http://xmlns.jcp.org/xml/ns/javaee/web-app_4_0.xsd" version="4.0">
    <context-param>
        <param-name>resteasy.preferJacksonOverJsonB</param-name>
        <param-value>false</param-value>
    </context-param>
</web-app>
```

If you didn't configure the above, you may see like following error.  
[Stack Overflow : (De)Serializing JSON on Thorntails Use JSON-B Instead of Jackson](https://stackoverflow.com/questions/61483229/deserializing-json-on-thorntails-use-json-b-instead-of-jackson).

```
2020-04-28 10:19:37,235 WARN  [org.jboss.as.jaxrs] (MSC service thread 1-6) 
WFLYRS0018: Explicit usage of Jackson annotation in a JAX-RS deployment; the
 system will disable JSON-B processing for the current deployment. Consider 
setting the 'resteasy.preferJacksonOverJsonB' property to 'false' to restore
 JSON-B.
```

### 8. Implement JAX-RS resource

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

### 9. Access to the RESTful Endpoint

The checklist resource is exposed in _/checklist_ path. So you can test it by executing the following command.

```bash
curl https://checklist-credential-free.azurewebsites.net/checklist
[{"date":"2022-03-21T00:00:00","description":"oekd list","id":1,"name":"hajshd"},{"date":"2022-03-21T00:00:00","description":"oekd list","id":2,"name":"hajshd"},{"date":"2022-03-21T00:00:00","description":"oekd list","id":3,"name":"hajshd"}]
```

As part of this sample, it is provided a [postman collection](postman/check_lists_request.postman_collection.json) which you can use to test the RESTful API. Just change _appUrl_ variable by your Azure App Service URL.