# Access Azure Database for MySQL using Managed Identities in Azure App Service JBoss EAP

In this sample, you can learn how to configure a Jakarta EE application to use Azure AD credentials, such as Managed Identities, to access Azure Database for MySQL.

This is a general Java EE (Jakarta EE) application. In the project, we used following technologies of Java EE.

* `JAX-RS (JavaTM API for RESTful Web Services)` 
* `JPA (JavaTM Persistence API)`
* `CDI`
* `JSON-B (JavaTM API for JSON Binding)`

### Prerequire for this sample

* Java SE 8 (or 11)
* Azure CLI command
* Azure Subscription
* git command
* Maven command
* MySQL client command
* jq command
* Bash
* pwgen as password generator

## Azure Setup
The following steps are required to setup Azure Database for MySQL and configure the application to access a database using a managed identity. All the steps can be performed in Azure CLI
For simplicity there are some variables defined.

```bash
RESOURCE_GROUP=[your resource group name]
MYSQL_HOST=[your mysql server name]
DATABASE_NAME=checklist
DATABASE_FQDN=${MYSQL_HOST}.mysql.database.azure.com
# Note that the connection url includes the password-free authentication plugin
MYSQL_CONNECTION_URL="jdbc:mysql://${DATABASE_FQDN}:3306/${DATABASE_NAME}?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.identity.extensions.jdbc.mysql.AzureMysqlAuthenticationPlugin&authenticationPlugins=com.azure.identity.extensions.jdbc.mysql.AzureMysqlAuthenticationPlugin"
APPSERVICE_NAME=[your app service name]
APPSERVICE_PLAN=[your app service plan name]
APP_IDENTITY_NAME=identity-jboss-passwordless
LOCATION=[your preferred location]
```

### login to your subscription

```bash
az login
```

### create a resource group

```bash
# create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION
```

### create mysql server

It is created with a mysql administrator account, but it won't be used as it wil be used the Azure AD admin account to perform the administrative tasks.

```bash
MYSQL_ADMIN_USER=azureuser
# Generating a random password for the MySQL user as it is mandatory
# mysql admin won't be used as Azure AD authentication is leveraged also for administering the database
MYSQL_ADMIN_PASSWORD=$(pwgen -s 15 1)
# create mysql flexible-server
az mysql flexible-server create \
    --name $MYSQL_HOST \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --admin-user $MYSQL_ADMIN_USER \
    --admin-password $MYSQL_ADMIN_PASSWORD \
    --public-access 0.0.0.0 \
    --tier Burstable \
    --sku-name Standard_B1ms \
    --storage-size 32 
```

Create a database for the application

```bash
# create mysql database
az mysql flexible-server db create -g $RESOURCE_GROUP -s $MYSQL_HOST -d $DATABASE_NAME
```

### Create application service

JBoss EAP requires Premium SKU.

```bash
# Create app service plan (premium required for JBoss EAP)
az appservice plan create --name $APPSERVICE_PLAN --resource-group $RESOURCE_GROUP --location $LOCATION --sku P1V3 --is-linux
# Create application service
az webapp create --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --plan $APPSERVICE_PLAN --runtime "JBOSSEAP:7-java8"
```

### Service connection creation

Service connection is required to allow the application to access the database using the Azure AD credentials. To active Azure AD credentials on MySQL flexible server it is necessary to assign an identity. The service connection is created using the Azure CLI 
command.

```bash
# create managed identity for mysql. By assigning the identity to the mysql server, it will enable Azure AD authentication
az identity create --name $APP_IDENTITY_NAME --resource-group $RESOURCE_GROUP --location $LOCATION
IDENTITY_ID=$(az identity show --name $APP_IDENTITY_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)
# create service connection. 
az webapp connection create mysql-flexible \
    --resource-group $RESOURCE_GROUP \
    --name $APPSERVICE_NAME \
    --tg $RESOURCE_GROUP \
    --server $MYSQL_HOST \
    --database $DATABASE_NAME \
    --client-type java \
    --identity-resource-id $IDENTITY_ID \
    --system-identity
```

The service connection performed the following configurations:
* Assigned a system managed identity to the application service.
* Enabled Azure AD authentication on the MySQL server.
* Created a user in the database corresponding to the system managed identity.
* Created an environment variable named AZURE_MYSQL_CONNECTIONSTRING in the application service. This variable contains the connection string without Authentication plugin parameters. It will be created a new environment variable with the authentication plugin parameters.

### Deploy the application

#### Create the database schema

Before deployinb the application it will be created the database schema by executing the script [init-db.sql](azure/init-db.sql). To perform this action it will be used mysql client, using the Azure AD Admin account, that corresponds to the logged-in user in Azure CLI. This account has been configured by the service connector.

To connect it can be necessary to create a firewall rule in the MySQL Server to allow the connection from the current IP address.

To get an access token for the current user it is used `az account get-access-token` command.

```bash
# CREATE DATABASE SCHEMA
# Create a temporary firewall rule to allow connections from current machine to the mysql server
MY_IP=$(curl http://whatismyip.akamai.com)
az mysql flexible-server firewall-rule create --resource-group $RESOURCE_GROUP --name $MYSQL_HOST --rule-name AllowCurrentMachineToConnect --start-ip-address ${MY_IP} --end-ip-address ${MY_IP}

# Create Database tables
RDBMS_ACCESS_TOKEN=$(az account get-access-token --resource-type oss-rdbms --output tsv --query accessToken)
mysql -h "${DATABASE_FQDN}" --user "${CURRENT_USER}" --enable-cleartext-plugin --password="$RDBMS_ACCESS_TOKEN" < init-db.sql

# Remove temporary firewall rule
az mysql flexible-server firewall-rule delete --resource-group $RESOURCE_GROUP --name $MYSQL_HOST --rule-name AllowCurrentMachineToConnect
```

#### Deploy the application

The application, as it will be explained later in this README, consists of a WAR package and also an startup script. So it is necessary to deploy both. It is also required to create an environment variable with the connection string with the authentication plugin parameters, this variable will be referenced in the startup script.

```bash
# Config JDBC connection string with passwordless authentication plugin
# Get the connection string generated by the service connector
PASSWORDLESS_URL=$(az webapp config appsettings list --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME | jq -c '.[] | select ( .name == "AZURE_MYSQL_CONNECTIONSTRING" ) | .value' | sed 's/"//g')
# Create a new environment variable with the connection string including the passwordless authentication plugin
PASSWORDLESS_URL=${PASSWORDLESS_URL}'&defaultAuthenticationPlugin=com.azure.identity.extensions.jdbc.mysql.AzureMysqlAuthenticationPlugin&authenticationPlugins=com.azure.identity.extensions.jdbc.mysql.AzureMysqlAuthenticationPlugin'
az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --settings "AZURE_MYSQL_CONNECTIONSTRING_PASSWORDLESS=${PASSWORDLESS_URL}"
```

Now the application can be deployed.

```bash
# Build WAR file
mvn clean package -DskipTests -f ../pom.xml

# Deploy the WAR and the startup script to the app service
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path ../target/ROOT.war --type war
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path ../src/main/webapp/WEB-INF/createMySQLDataSource.sh --type startup
```

### All together
In [deploy.sh](azure/deploy.sh) script you can find all the steps required to setup the infrastructure and deploy the sample application.

### Clean-up Azure resources
Just delete the resource group where all the resources were created
```bash
az group delete $RESOURCE_GROUP
```

## Overview of the code

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

### 3. Add dependency for JDBC passwordless authentication plugin for MySQL

```xml
<dependency>
    <groupId>com.azure</groupId>
     <artifactId>azure-identity-extensions</artifactId>
     <version>1.0.0</version>
</dependency>
```

### 4. Create a DataSource with JNDI on your Application Server with no password validation 

In order to create a DataSource, you need to create a DataSource on your Application Server.  
Following [createMySQLDataSource.sh](src/main/webapp/WEB-INF/createMySQLDataSource.sh) script create the DataSource on JBoss EAP with JBoss CLI command.

This script references the new environment variable `AZURE_MYSQL_CONNECTIONSTRING_PASSWORDLESS` that was created in the deployment script that contains the passwordless configuration.

```bash
#!/bin/bash
# In order to use the variables in CLI scripts
# https://access.redhat.com/solutions/321513
sed -i -e "s|.*<resolve-parameter-values.*|<resolve-parameter-values>true</resolve-parameter-values>|g" /opt/eap/bin/jboss-cli.xml
/opt/eap/bin/jboss-cli.sh --connect <<EOF
data-source add --name=CredentialFreeDataSourceDS \
--jndi-name=java:jboss/datasources/CredentialFreeDataSource \
--connection-url=${AZURE_MYSQL_CONNECTIONSTRING_PASSWORDLESS} \
--driver-name=ROOT.war_com.mysql.cj.jdbc.Driver_8_0 \
--min-pool-size=5 \
--max-pool-size=20 \
--blocking-timeout-wait-millis=5000 \
--enabled=true \
--driver-class=com.mysql.cj.jdbc.Driver \
--jta=true \
--use-java-context=true \
--valid-connection-checker-class-name=org.jboss.jca.adapters.jdbc.extensions.mysql.MySQLValidConnectionChecker \
--exception-sorter-class-name=com.mysql.cj.jdbc.integration.jboss.ExtendedMysqlExceptionSorter
exit
EOF
```

### 5. Create a persistence unit config for JPA on persistence.xml

After created the DataSource, you need create persistence unit config on [persistence.xml](src/main/resources/META-INF/persistence.xml) which is the configuration file of JPA.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<persistence version="2.2" xmlns="http://xmlns.jcp.org/xml/ns/persistence" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://xmlns.jcp.org/xml/ns/persistence http://xmlns.jcp.org/xml/ns/persistence/persistence_2_2.xsd">
  <persistence-unit name="CredentialFreeDataSourcePU" transaction-type="JTA">
    <jta-data-source>java:jboss/datasources/CredentialFreeDataSource</jta-data-source>
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

    @PersistenceContext(unitName = "CredentialFreeDataSourcePU")
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
curl https://jboss-passwordless.azurewebsites.net/checklist
[{"date":"2022-03-21T00:00:00","description":"oekd list","id":1,"name":"hajshd"},{"date":"2022-03-21T00:00:00","description":"oekd list","id":2,"name":"hajshd"},{"date":"2022-03-21T00:00:00","description":"oekd list","id":3,"name":"hajshd"}]
```

As part of this sample, it is provided a [postman collection](postman/check_lists_request.postman_collection.json) which you can use to test the RESTful API. Just change _appUrl_ variable by your Azure App Service URL.