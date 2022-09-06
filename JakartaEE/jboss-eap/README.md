# Access Azure Database for MySQL using Managed Identities in Azure App Service JBoss EAP

In this sample, you can learn how to configure a Jakarta EE application to use Azure AD credentials, such as Managed Identities, to access Azure Database for MySQL. You will also learn how to setup the Data source in JBoss EAP to override some typical validations that you no longer need, such as the password validation.

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
MYSQL_CONNECTION_URL="jdbc:mysql://${DATABASE_FQDN}:3306/${DATABASE_NAME}?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin&authenticationPlugins=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin"
APPSERVICE_NAME=checklist-credential-free
APPSERVICE_PLAN=asp-checklist-credential-free
LOCATION=[your preferred location]
MYSQL_ADMIN_USER=azureuser
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
It is created with an administrator account, but it won't be used as it wil be used the Azure AD admin account to perform the administrative tasks.
```bash
MYSQL_ADMIN_USER=azureuser
# Generating a random password for the MySQL user as it is mandatory
# mysql admin won't be used as Azure AD authentication is leveraged also for administering the database
MYSQL_ADMIN_PASSWORD=$(pwgen -s 15 1)
# create mysql server
az mysql server create \
    --name $MYSQL_HOST \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --admin-user $MYSQL_ADMIN_USER \
    --admin-password $MYSQL_ADMIN_PASSWORD \
    --public-network-access 0.0.0.0 \
    --sku-name B_Gen5_1 
```
When creating mysql server, it is necessary to create an Azure AD administrator account to enable Azure AD authentication. The current azure cli user will be configured as Azure AD administrator account.

To get the current user required data:
```bash
CURRENT_USER=$(az account show --query user.name -o tsv)
CURRENT_USER_OBJECTID=$(az ad user show --id $CURRENT_USER --query id -o tsv)
```
Also note the current user domain
```bash
CURRENT_USER_DOMAIN=$(cut -d '@' -f2 <<< $CURRENT_USER)
```
Then, create the Azure AD administrator account:
```bash
# create mysql server AAD admin user
az mysql server ad-admin create --server-name $MYSQL_HOST --resource-group $RESOURCE_GROUP --object-id $CURRENT_USER_OBJECTID --display-name $CURRENT_USER
```
Create a database for the application
```bash
# create mysql database
az mysql db create -g $RESOURCE_GROUP -s $MYSQL_HOST -n $DATABASE_NAME
```
### Create application service
JBoss EAP requires Premium SKU. When creating the application service, it is specified to use a system managed identity. 
```bash
```
```bash
# Create app service plan (premium required for JBoss EAP)
az appservice plan create --name $APPSERVICE_PLAN --resource-group $RESOURCE_GROUP --location $LOCATION --sku P1V3 --is-linux
# Create application service
az webapp create --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --plan $APPSERVICE_PLAN --runtime "JBOSSEAP:7-java8" --assign-identity [system]
```
The authentication plugin is also compatible with User Assigned managed identity, it requires to include the clientId of the managed identity in the JDBC url as parameter _clientid_. So the connection url would be changed to the following.
```bash
MYSQL_CONNECTION_URL="jdbc:mysql://${DATABASE_FQDN}:3306/${DATABASE_NAME}?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin&authenticationPlugins=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin&clientid=$user_assigned_identity_client_id"
```
For simplicity, the rest of the sample will assume system assigned managed identity.
### Service connection creation
Service connection with managed identities is not yet supported for App Services. All required steps will be performed manually. To summarize, the steps are:
1. Create a temporary firewall rule to allow access to the mysql server. MySQL server was configured to allow only other Azure services to access it. To allow the deployment box to perform action on MySQL it is necessary to open a connection. After all actions are performed it will be deleted.
1. Get the App Service identity. MySQL requires the clientId/applicationId, and az webapp returns the objectId, so it is necessary to perform an additional request to Azure AD to get the clientId.
1. Create a mysql user for the application identity and grant permissions to the database. For this action, it is necessary to connect to the database, for instance using _mysql_ client tool. The current user, an Azure AD admin configured above, will be used to connect to the database. `az account get-access-token` can be used to get an access token.
1. Remove the temporary firewall rule.

Note: The database tables will be created taking advantage of the temporary firewall rule
```bash
# 0. Create a temporary firewall rule to allow connections from current machine to the mysql server
MY_IP=$(curl http://whatismyip.akamai.com)
az mysql server firewall-rule create --resource-group $RESOURCE_GROUP --server $MYSQL_HOST --name AllowCurrentMachineToConnect --start-ip-address ${MY_IP} --end-ip-address ${MY_IP}
# 1. Get web application managed identity
APPSERVICE_IDENTITY_OBJID=$(az webapp show --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --query identity.principalId -o tsv)
# 2. IMPORTANT: It is required the clientId/appId, and previous command returns object id. So next step retrieve the client id
APPSERVICE_IDENTITY_APPID=$(az ad sp show --id $APPSERVICE_IDENTITY_OBJID --query appId -o tsv)
# 3. Create mysql user in the database and grant permissions the database. Note that login is performed using the current logged in user as AAD Admin and using an access token
RDBMS_ACCESS_TOKEN=$(az account get-access-token --resource-type oss-rdbms --output tsv --query accessToken)
mysql -h "${DATABASE_FQDN}" --user "${CURRENT_USER}@${MYSQL_HOST}" --enable-cleartext-plugin --password="$RDBMS_ACCESS_TOKEN" << EOF 
SET aad_auth_validate_oids_in_tenant = OFF;

DROP USER IF EXISTS '${APPSERVICE_LOGIN_NAME}'@'%';

CREATE AADUSER '${APPSERVICE_LOGIN_NAME}' IDENTIFIED BY '${APPSERVICE_IDENTITY_APPID}';

GRANT ALL PRIVILEGES ON ${DATABASE_NAME}.* TO '${APPSERVICE_LOGIN_NAME}'@'%';

FLUSH privileges;
EOF

# 4. Create Database tables
mysql -h "${DATABASE_FQDN}" --user "${CURRENT_USER}@${MYSQL_HOST}" --enable-cleartext-plugin --password="$RDBMS_ACCESS_TOKEN" < init-db.sql

# 5. Remove temporary firewall rule
az mysql server firewall-rule delete --resource-group $RESOURCE_GROUP --server $MYSQL_HOST --name AllowCurrentMachineToConnect
```

### Deploy the application
The application, as it will be explained later in this README, consists of a WAR package and also an startup script. So it is necessary to deploy both.

It is also necessary to pass the connection url and the login name to the application using environment variables. Note that the username includes the domain and also mysql hostname. So it will be something like `checklistapp@mydomain.com@mysupersql`

```bash
# 6. Build WAR file
mvn clean package
# 7. Set environment variables for the web application pointing to the database and using the appservice identity login
APPSERVICE_LOGIN_NAME='checklistapp@'${CURRENT_USER_DOMAIN}
az webapp config appsettings set -g $RESOURCE_GROUP -n $APPSERVICE_NAME --settings MYSQL_CONNECTION_URL=${MYSQL_CONNECTION_URL} MYSQL_USER=${APPSERVICE_LOGIN_NAME}'@'${MYSQL_HOST}
# 8. Create webapp deployment. It is deployed the war package and the startup script.
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
data-source add --name=CredentialFreeDataSourceDS \
--jndi-name=java:jboss/datasources/CredentialFreeDataSource \
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
curl https://checklist-credential-free.azurewebsites.net/checklist
[{"date":"2022-03-21T00:00:00","description":"oekd list","id":1,"name":"hajshd"},{"date":"2022-03-21T00:00:00","description":"oekd list","id":2,"name":"hajshd"},{"date":"2022-03-21T00:00:00","description":"oekd list","id":3,"name":"hajshd"}]
```

As part of this sample, it is provided a [postman collection](postman/check_lists_request.postman_collection.json) which you can use to test the RESTful API. Just change _appUrl_ variable by your Azure App Service URL.