# Access Azure Database for PostgreSQL using Managed Identities for Quarkus applications

In this sample, you can learn how to configure a Quarkus application to use Azure Database for PostgreSQL using Managed Identities. This sample includes the steps to deploy the application in:

* Azure Container Apps using JAR packaging

> NOTE: This sample is forked from the [hibernate-orm-panache-quickstart](https://github.com/quarkusio/quarkus-quickstarts/tree/6edfc7dcc700f3c9e7a96c32c019e4cd119e5959/hibernate-orm-panache-quickstart) in the [quarkus-quickstarts](https://github.com/quarkusio/quarkus-quickstarts) repo. You could refer to the original README.md file for more information about the sample itself. 

This is a minimal CRUD service exposing a couple of endpoints over REST,
with a front-end based on Angular so you can play with it from your browser.

While the code is surprisingly simple, under the hood this is using:
- RESTEasy to expose the REST endpoints
- Hibernate ORM with Panache to perform the CRUD operations on the database
- An Azure Database for PostgreSQL
- ArC, the CDI inspired dependency injection tool with zero overhead
- The high performance Agroal connection pool
- Infinispan based caching
- All safely coordinated by the Narayana Transaction Manager

## Prerequisite for this sample

* JDK 11+
* [Azure CLI](/cli/azure/overview). This tutorial requires you to run the latest [edge build of Azure CLI](https://github.com/Azure/azure-cli/blob/dev/doc/try_new_features_before_release.md). [Download and install the edge builds](https://github.com/Azure/azure-cli#edge-builds) for your platform.
* Azure Subscription
* Git command
* Maven command
* psql client
* Bash
* pwgen as password generator

All samples were developed and tested using Visual Studio Code on WSL2 (Windows Subsystem for Linux 2). Some tools can be different depending on your OS.

## Azure Setup

The following steps are required to set up an Azure Database for PostgreSQL and configure the application to access a database using a managed identity. All the steps can be performed in Azure CLI
For simplicity there are some variables defined.

```bash
RESOURCE_GROUP=[YOUR RESOURCE GROUP]
LOCATION=[YOUR PREFERRED LOCATION]
POSTGRESQL_HOST=[YOUR POSTGRESQL HOST] 
POSTGRESQL_DATABASE_NAME=quarkustest

# CONTAINER APPS RELATED VARIABLES
ACR_NAME=passwordlessacr
CONTAINERAPPS_ENVIRONMENT=acaenv-passwordless
CONTAINERAPPS_NAME=aca-passwordless
CONTAINERAPPS_CONTAINERNAME=passwordless-container
```

### login to your subscription

```bash
az login
```

### create a resource group

```bash
az group create --name $RESOURCE_GROUP --location $LOCATION
```

### Create PostgreSQL server

It is created with an administrator account, but it won't be used as it wil be used the Azure AD admin account to perform the administrative tasks.

```bash
POSTGRESQL_ADMIN_USER=azureuser
POSTGRESQL_ADMIN_PASSWORD=$(pwgen -s 15 1)
# create postgresql server
az postgres server create \
    --name $POSTGRESQL_HOST \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --admin-user $POSTGRESQL_ADMIN_USER \
    --admin-password "$POSTGRESQL_ADMIN_PASSWORD" \
    --public 0.0.0.0 \
    --sku-name GP_Gen5_2 \
    --version 11 \
    --storage-size 5120 
```
> NOTE: This command will generate a random password for the PostgreSQL admin user as it is mandatory. Postgres admin won't be used as Azure AD authentication is leveraged also for administering the database.

Create a database for the application:

```bash
az postgres db create \
    -g $RESOURCE_GROUP \
    -s $POSTGRESQL_HOST \
    -n $POSTGRESQL_DATABASE_NAME
```

### Create Azure Container App

It requires an Azure Container Registry to store the container image. The container is built from Docker file directly in Azure Container Registry. Then and deployed to Azure Container App. The system managed identity will be granted to pull images from Azure Container Registry and access to the database.

#### Create Azure Container Registry

First, create an Azure Container Registry (ACR) to store the container image.

```bash
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Standard --location $LOCATION
```

#### Create Azure Container App

It is necessary to register Container Apps extension on the Azure CLI. This step is only required once. If it is already present in the environment it can be skipped.

```bash
az extension add --name containerapp --upgrade
# register Microsoft.App namespace provider
az provider register --namespace Microsoft.App
```

Create an Azure Container App environment.

```bash
az containerapp env create \
    --name $CONTAINERAPPS_ENVIRONMENT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION
```

Build the container image. To build the container it is not necessary having Docker installed in the local machine. The container image is built directly in Azure Container Registry. The pom.xml contains a profile named _buildAcr_ to build the container image. For more details on the implementation see [this article](https://techcommunity.microsoft.com/t5/fasttrack-for-azure/using-azure-container-registry-to-build-docker-images-for-java/ba-p/3563875).

Build JAR file and push to ACR using the Maven `buildAcr` profile:
```bash
mvn clean package -DskipTests -PbuildAcr -DRESOURCE_GROUP=$RESOURCE_GROUP -DACR_NAME=$ACR_NAME
```

Create the Azure Container App. This step will create the container referencing the container image in the registry, see _image_ parameter. The system identity of the container app is used to pull the image, see _registry-identity_ and _system-assigned_ parameter.
    
```bash
az containerapp create \
    --name $CONTAINERAPPS_NAME \
    --resource-group $RESOURCE_GROUP \
    --environment $CONTAINERAPPS_ENVIRONMENT \
    --container-name $CONTAINERAPPS_CONTAINERNAME \
    --registry-identity system \
    --system-assigned \
    --registry-server $ACR_NAME.azurecr.io \
    --image $ACR_NAME.azurecr.io/hibernate-orm-panache-quickstart:1.0.0-SNAPSHOT \
    --ingress external \
    --target-port 8080 \
    --cpu 1 \
    --memory 2
```


At this point the application is deployed and accessible from the internet, but it doesn't work as there is no database connection configured.

#### Create a service connection to the database

Service connection will create a new user in the database linked to the system managed identity of the container app. The user will be granted to access to the database.

The logged-in user in Azure CLI is configured as PostgreSQL Azure AD administrator.

Create the service connection:

```bash
az containerapp connection create postgres \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINERAPPS_NAME \
    --container $CONTAINERAPPS_CONTAINERNAME \
    --tg $RESOURCE_GROUP \
    --server $POSTGRESQL_HOST \
    --database $POSTGRESQL_DATABASE_NAME \
    --client-type java \
    --system-identity
```

Now the application is running and connected to the database.

### All together

A script has been provided to create and deploy the application to Azure Container Apps. You can change the environment variables defined in the script and then run the following command:

```bash
.azure/deploy-on-containerapp.sh
```

### Clean-up Azure resources

Just delete the resource group where all the resources were created

```bash
az group delete $RESOURCE_GROUP
```

## Run locally

With the resources created in the `Azure Setup` step, you can also run the application locally.

The service connection command in last step will add current signed-in user of Azure CLI as the Azure AD admin of the PostgreSQL database server. So we can use the credential of the current signed-in user to run the application locally.

To connect to Azure Database for PostgreSQL requires adding a firewall rule for your local machine:
```bash
az postgres server firewall-rule create \
    --resource-group $RESOURCE_GROUP \
    --name $POSTGRESQL_HOST-database-allow-local-ip \
    --server $POSTGRESQL_HOST \
    --start-ip-address $(curl -4 ifconfig.co) \
    --end-ip-address $(curl -4 ifconfig.co) \
    --output tsv
```

First set the CURRENT_USER:
```bash
export CURRENT_USERNAME=$(az ad signed-in-user show --query userPrincipalName --output tsv)
```

Then run the following command to run the application:

```bash
./mvnw quarkus:dev
```
