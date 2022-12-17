# Access Azure Database for PostgreSQL using Managed Identities in Azure App Service Tomcat 10

In this sample, you can learn how to configure a Tomcat application to use Azure AD credentials, such as Managed Identities, to access Azure Database for PostgreSQL.

This is a general Tomcat application that uses some technologies of Jakarta EE:

* `JAX-RS (JavaTM API for RESTful Web Services)` 
* `JPA (JavaTM Persistence API)`
* `CDI`
* `JSON-B (JavaTM API for JSON Binding)`

The code details are described in [README_CODE.md](README_CODE.md).

## Prerequire for this sample

* Java 11+
* Azure CLI command
* Azure Subscription
* git command
* Maven command
* MySQL client command
* jq command
* Bash
* pwgen as password generator

## Azure Setup

The following steps are required to setup Azure Database for PostgreSQL and configure the application to access a database using a managed identity. All the steps can be performed in Azure CLI

For simplicity there are some variables defined.

```bash
RESOURCE_GROUP=[YOUR RESOURCE GOUP NAME]
POSTGRESQL_HOST=[YOUR POSTGRESQL HOST NAME]
DATABASE_NAME=checklist
APPSERVICE_NAME=[YOUR APPLICATION NAME]
APPSERVICE_PLAN=[YOUR APPLICATION PLAN NAME]
LOCATION=[YOUR PREFERRED LOCATON]
DATABASE_FQDN=${POSTGRESQL_HOST}.postgres.database.azure.com
PSQL_CONNECTION_URL="jdbc:postgresql://${DATABASE_FQDN}:5432/${DATABASE_NAME}?sslmode=require&authenticationPluginClassName=com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin"
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

### create Azure Database for PostgreSQL flexible server

It is created with an administrator account so it is necessary to provide a user name and password. This account won't be used as it will be used the Azure AD admin account to perform the administrative tasks. The password is automatically generated with the `pwgen` command.

```bash

POSTGRESQL_ADMIN_USER=azureuser
# Generating a random password for the PostgreSQL admin user as it is mandatory
# postgres admin won't be used as Azure AD authentication is leveraged also for administering the database
POSTGRESQL_ADMIN_PASSWORD=$(pwgen -s 15 1)
# create postgresql server
az postgres flexible-server create \
    --name $POSTGRESQL_HOST \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --admin-user $POSTGRESQL_ADMIN_USER \
    --admin-password "$POSTGRESQL_ADMIN_PASSWORD" \
    --public-access 0.0.0.0 \
    --tier Burstable \
    --sku-name Standard_B1ms \
    --version 14 \
    --storage-size 32 
```

Create a database for the application

```bash
# create postgres database
az postgres flexible-server db create \
    -g $RESOURCE_GROUP \
    -s $POSTGRESQL_HOST \
    -d $DATABASE_NAME
```

### Create application service

The application is prepared for Tomcat 10. It cannot be deployed on Tomcat 9 as the application references jakarta.

```bash
# Create app service plan
az appservice plan create --name $APPSERVICE_PLAN --resource-group $RESOURCE_GROUP --location $LOCATION --sku B1 --is-linux
# Create application service
az webapp create --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --plan $APPSERVICE_PLAN --runtime "TOMCAT:10.0-java11"
```

### Service connection creation

The service connector will perform all required steps to connect the application to the database. It will create a System managed identity and assign the required roles to access the database.

```bash
# create service connection. 
az webapp connection create postgres-flexible \
    --resource-group $RESOURCE_GROUP \
    --name $APPSERVICE_NAME \
    --tg $RESOURCE_GROUP \
    --server $POSTGRESQL_HOST \
    --database $DATABASE_NAME \
    --client-type java \
    --system-identity
```

After executing this command:

* The App Service is configured with a System managed identity
* The PostgreSQL server is configured with an Azure AD administrator, in this case the logged-in user in Azure CLI.
* There is a new user created in the database server corresponding to the System managed identity, and it granted to access to the database.

### Deploy the application

As part of the configuration, the service connector defines a environment variable in the App Service, AZURE_POSTGRESQL_CONNECTIONSTRING. This a generic connection string without authentication plugin, so it is necessary to enhance it with the authentication plugin and then pass to the application using CATALINA_OPTS.

```bash
# Set connection url environment variables. It is necessary to pass it on CATALINA_OPTS environment variable
az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --settings 'CATALINA_OPTS=-DdbUrl="${AZURE_POSTGRESQL_CONNECTIONSTRING}&authenticationPluginClassName=com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin"'
```

Be mindful of escape quotes in the command above. The single quote are required to do not replace $AZURE_POSTGRESQL_CONNECTIONSTRING with the value of the environment variable in the local CLI. During runtime that variable will be replace with the existing value in the App Service.

Finally deploy the application.

```bash
# Build WAR file
mvn clean package
# Create webapp deployment
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path target/app.war --type war
```

### All together

In [deploy.sh](azure/deploy.sh) script you can find all the steps required to setup the infrastructure and deploy the sample application.

### Clean-up Azure resources

Just delete the resource group where all the resources were created
```bash
az group delete --name $RESOURCE_GROUP
```
