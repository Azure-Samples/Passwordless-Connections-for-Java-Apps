# Access Azure Database for PostgreSQL Flexible Server using Managed Identities for Spring Boot applications

In this sample, you can learn how to configure a Spring Boot application to use Azure Database for PostgreSQL Flexible Server using Managed Identities. This sample includes the steps to deploy the application in:

* Azure Spring Apps using JAR packaging
* Azure App Service on Tomcat using WAR packaging
* Azure App Service on Java SE using JAR packaging
* Azure Container Apps using JAR packaging

## Prerequire for this sample

* Java SE 8 (or 11)
* Azure CLI command
* Azure Subscription
* git command
* Maven command
* psql client
* Bash
* pwgen as password generator

All samples were developed and tested using Visual Studio Code on WSL2 (Windows Subsystem for Linux 2). Some tools can be different depending on your OS.

If you want to go on the details of code please read the [README_CODE.md](README_CODE.md) file.

# Azure Setup

The following steps are required to setup an Azure Database for PostgreSQL Flexible Server and configure the application to access a database using a managed identity. All the steps can be performed in Azure CLI
For simplicity there are some variables defined.

```bash
RESOURCE_GROUP=[YOUR RESOURCE GROUP]
POSTGRESQL_HOST=[YOUR POSTGRESQL HOST] 
DATABASE_NAME=checklist
# Note that the connection url does not includes the password-free authentication plugin
# The configuration is injected by spring-cloud-azure-starter-jdbc
LOCATION=[YOUR PREFERRED LOCATION]
POSTGRESQL_ADMIN_USER=azureuser
```

Depending if the hosting environment is Azure App Services or Azure Spring Apps there can be some differences.

For Azure Spring Apps:

```bash
APPSERVICE_NAME=[YOUR APPLICATION NAME]
SPRING_APPS_SERVICE=[YOUR SPRING APPS SERVICE NAME]
```

For Azure App Services, the following variables are defined:

```bash
APPSERVICE_NAME=[YOUR APPSERVICE NAME]
APPSERVICE_PLAN=[YOUR APPSERVICE PLAN NAME]
```

For Azure Container Apps:

```bash
# CONTAINER APPS RELATED VARIABLES
ACR_NAME=credenialfreeacr
CONTAINERAPPS_ENVIRONMENT=acaenv-passwordless
CONTAINERAPPS_NAME=aca-passwordless
CONTAINERAPPS_CONTAINERNAME=passwordless-container
```

## login to your subscription

```bash
az login
```

## create a resource group

```bash
# create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION
```

## Create PostgreSQL Flexible Server

It is created with an administrator account, but it won't be used as it wil be used the Azure AD admin account to perform the administrative tasks.

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

## Create the hosting environment

As mentioned above, the hosting environment can be Azure Spring Apps or Azure App Services.

### Create Azure Spring Apps

It only requires:

* Create Azure Spring Apps service
* Create an application
* Create a service connection
* Then deploy the application.

#### Create Azure Spring Apps service

```bash
# Create Spring App service
az spring create --name ${SPRING_APPS_SERVICE} \
    --resource-group ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --sku Basic
```

#### Create an application

The application will be created with a public endpoint to make it accessible from the internet.

```bash
# Create Application
az spring app create --name ${APPSERVICE_NAME} \
    -s ${SPRING_APPS_SERVICE} \
    -g ${RESOURCE_GROUP} \
    --assign-endpoint true 
```

#### Create a service connection

```bash
# create service connection.The service connection creates the managed identity if not exists.
az spring connection create postgres-flexible \
    --resource-group $RESOURCE_GROUP \
    --service $SPRING_APPS_SERVICE \
    --connection demo_connection \
    --app ${APPSERVICE_NAME} \
    --deployment default \
    --tg $RESOURCE_GROUP \
    --server $POSTGRESQL_HOST \
    --database $DATABASE_NAME \
    --system-identity \
    --client-type springboot
```

#### Build and deploy the application

The application will be deployed as a jar file, so pom.xml is used. To make the application work with the Azure Spring Cloud JDBC starter, it is necessary to configure the following property:

```properties
spring.datasource.azure.passwordless-enabled=true
```

It can be configured as an environment variable in the deployment.

```bash
# Build JAR file
mvn clean package -f pom.xml

# Deploy application
az spring app deploy --name $APPSERVICE_NAME\
    --resource-group $RESOURCE_GROUP \
    --service $SPRING_APPS_SERVICE \
    --artifact-path target/app.jar \
    --env "SPRING_DATASOURCE_AZURE_PASSWORDLESSENABLED=true"
```

### Create application service

When deploying to Azure App Services, it can be deployed as JavaSE standalone or as a WAR file. The WAR file requires a Tomcat server to run. The JavaSE standalone is a self-contained application that embeds a Tomcat server.

So first create the Application Service Plan

```bash
# Create app service plan
az appservice plan create --name $APPSERVICE_PLAN --resource-group $RESOURCE_GROUP --location $LOCATION --sku B1 --is-linux
```

For Standalone JavaSE:

```bash
# Create application service
az webapp create --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --plan $APPSERVICE_PLAN --runtime "JAVA:8-jre8"
```

For Tomcat:

```bash
# Create application service
az webapp create --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --plan $APPSERVICE_PLAN --runtime "TOMCAT:9.0-jre8"
```

If it is not specified, the service connection will create a System managed identity to connect to the database.

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
    --client-type springboot \
    --system-identity
```

After executing this command:

* The App Service is configured with a System managed identity.
* The App Service has an environment variable with the connection string to the database without the password and with no Passwordless authentication configured.
* The PostgreSQL server is configured with an Azure AD administrator, in this case the logged-in user in Azure CLI.
* There is a new user created in the database server corresponding to the System managed identity, and it granted to access to the database.

### Deploy the application on App Service

If the application is deployed on Tomcat it is necessary to build a war file, if deployed as JavaSE it is necessary to build a jar file. For that purpose there are two pom.xml files.

* pom.xml generates a jar file
* pom-war.xml generates a war file
The main difference is the packaging type, and for war packaging it is necessary to include the following dependency:

```xml
<!-- Required to deploy WAR on Tomcat -->
<dependency>
 <groupId>org.springframework.boot</groupId>
 <artifactId>spring-boot-starter-tomcat</artifactId>
 <scope>provided</scope>
</dependency>
```

In both cases it is necessary to include the following dependency to use the Azure Spring Cloud JDBC starter:

```xml
<!--Passwordless spring starter for postgresql -->
<dependency>
	<groupId>com.azure.spring</groupId>
	<artifactId>spring-cloud-azure-starter-jdbc-postgresql</artifactId>
	<version>4.5.0</version>
</dependency>
```

To make the application work with the Azure Spring Cloud JDBC starter, it is necessary to configure the following property:

```properties
spring.datasource.azure.credential-free-enable=true
```

It can be configured as appservice configuration settings:

```bash	
# Set environment variables to allow spring starter to enhance the database connection to use the AAD authentication plugin
az webapp config appsettings set -g $RESOURCE_GROUP -n $APPSERVICE_NAME --settings "SPRING_DATASOURCE_AZURE_PASSWORDLESSENABLED=true"
```

#### Deploy on Tomcat

```bash
# Build WAR file
mvn clean package -f pom-war.xml
# Create webapp deployment
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path target/app.war --type war
```

#### Deploy on JavaSE

```bash
# Build JAR file
mvn clean package -f pom.xml

# Create webapp deployment
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path target/app.jar --type jar
```

## Create Azure Container App

It requires an Azure Container Registry to store the container image. The container is built from Docker file directly in Azure Container Registry. Then and deployed to Azure Container App. The system managed identity will be granted to pull images from Azure Container Registry and access to the database.

### Create Azure Container Registry

First, create an Azure Container Registry to store the container image.

```bash
# create an Azure Container Registry (ACR) to hold the images for the demo
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Standard --location $LOCATION
```

### Create Azure Container App

It is necessary to register Container Apps extension on the Azure CLI. This step is only required once. If it already present in the environment it can be skipped.

```bash
# register container apps extension
az extension add --name containerapp --upgrade
# register Microsoft.App namespace provider
az provider register --namespace Microsoft.App
```

Create the Azure Container App environment.

```bash
# create an azure container app environment
az containerapp env create \
    --name $CONTAINERAPPS_ENVIRONMENT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION
```

Build the container image. To build the container it is not necessary having Docker installed in the local machine. The container image is built directly in Azure Container Registry. The pom.xml contains a profile named _buildAcr_ to build the container image. For more details on the implementation see [this article](https://techcommunity.microsoft.com/t5/fasttrack-for-azure/using-azure-container-registry-to-build-docker-images-for-java/ba-p/3563875).

```bash
# Build JAR file and push to ACR using buildAcr profile
mvn clean package -DskipTests -PbuildAcr -DRESOURCE_GROUP=$RESOURCE_GROUP -DACR_NAME=$ACR_NAME
```

Create the Azure Container App. This step will create the container referencing the container image in the registry., see _image_ parameter. The system identity of the container app is used to pull the image, see _registry-identity_ and _system-assigned_ parameter.
    
```bash
# Create the container app
az containerapp create \
    --name ${CONTAINERAPPS_NAME} \
    --resource-group $RESOURCE_GROUP \
    --environment $CONTAINERAPPS_ENVIRONMENT \
    --container-name $CONTAINERAPPS_CONTAINERNAME \
    --registry-identity system \
    --system-assigned \
    --registry-server $ACR_NAME.azurecr.io \
    --image $ACR_NAME.azurecr.io/spring-checklist-passwordless:0.0.1-SNAPSHOT \
    --ingress external \
    --target-port 8080 \
    --cpu 1 \
    --memory 2 \
    --env-vars "SPRING_DATASOURCE_AZURE_PASSWORDLESSENABLED=true"
```

Note that the environment variable _SPRING_DATASOURCE_AZURE_PASSWORDLESSENABLED_ is set to _true_ to enable the passwordless connection.

At this point the application is deployed and accessible from the internet, but it doesn't work as there is no database connection configured.

### Create a service connection to the database

Service connection will create a new user in the database linked to the system managed identity of the container app. The user will be granted to access to the database.

The logged-in user in Azure CLI is configured as PostgreSQL Azure AD administrator.

```bash
# create service connection.
az containerapp connection create postgres-flexible \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINERAPPS_NAME \
    --container $CONTAINERAPPS_CONTAINERNAME \
    --tg $RESOURCE_GROUP \
    --server $POSTGRESQL_HOST \
    --database $DATABASE_NAME \
    --client-type springboot \
    --system-identity
```

Now the application is running and connected to the database.

## All together

It is provided 4 scripts to create and deploy the environment depending on the hosting environment.

* Azure Spring Apps: [deploy-on-springapp.sh](azure/deploy-on-springapp.sh)
* Tomcat on App Service: [deploy-on-tomcat.sh](azure/deploy-on-tomcat.sh)
* Standalone JavaSE on App Service: [deploy-on-javase.sh](azure/deploy-on-javase.sh).
* Azure Container Apps: [deploy-on-containerapp.sh](azure/deploy-on-containerapp.sh)

## Clean-up Azure resources

Just delete the resource group where all the resources were created

```bash
az group delete --name $RESOURCE_GROUP
```
