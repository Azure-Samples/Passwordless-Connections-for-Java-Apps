RESOURCE_GROUP=rg-spring-containerapp-passwordless
export POSTGRESQL_HOST=psql-spring-containerapp-passwordless
export POSTGRESQL_DATABASE_NAME=quarkustest
POSTGRESQL_DATABASE_FQDN=${POSTGRESQL_HOST}.postgres.database.azure.com
# Note that the connection url does not includes the password-free authentication plugin
# The configuration is injected by spring-cloud-azure-starter-jdbc

# CONTAINER APPS RELATED VARIABLES
ACR_NAME=passwordlessacr
CONTAINERAPPS_ENVIRONMENT=acaenv-passwordless
CONTAINERAPPS_NAME=aca-passwordless
CONTAINERAPPS_CONTAINERNAME=passwordless-container

LOCATION=eastus
POSTGRESQL_ADMIN_USER=azureuser
# Generating a random password for the PostgreSQL admin user as it is mandatory
# postgres admin won't be used as Azure AD authentication is leveraged also for administering the database
POSTGRESQL_ADMIN_PASSWORD=$(pwgen -s 15 1)

# Get current logged-in user
export CURRENT_USER=$(az account show --query user.name -o tsv)
CURRENT_USER_ID=$(az ad user show --id "$CURRENT_USER" --query id -o tsv)

# create resource group if not exists
az group show -n $RESOURCE_GROUP  1> /dev/null
if [ $? != 0 ]; then
  set -e
  echo "Resource group with name" $RESOURCE_GROUP "could not be found. Creating new resource group.."
  az group create --name $RESOURCE_GROUP --location $LOCATION
  set +e
fi

# create postgresql server if not exists
az postgres server show -g $RESOURCE_GROUP -n $POSTGRESQL_HOST 1> /dev/null
if [ $? != 0 ]; then
  set -e
  echo "PostgreSQL server with name" $POSTGRESQL_HOST "could not be found. Creating new PostgreSQL server.."
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
  set +e
fi

set -e
# create postgres database
az postgres db create \
    -g $RESOURCE_GROUP \
    -s $POSTGRESQL_HOST \
    -n $POSTGRESQL_DATABASE_NAME
set +e

# create an Azure Container Registry (ACR) to hold the images for the demo if not exists
az acr show -g $RESOURCE_GROUP -n $ACR_NAME 1> /dev/null
if [ $? != 0 ]; then
  set -e
  az acr create \
      --resource-group $RESOURCE_GROUP \
      --name $ACR_NAME \
      --sku Standard \
      --location $LOCATION
  set +e
fi

# register container apps extension
az extension add --name containerapp --upgrade

# create an azure container app environment if not exists
az containerapp env show -g $RESOURCE_GROUP -n $CONTAINERAPPS_ENVIRONMENT 1> /dev/null
if [ $? != 0 ]; then
  set -e
  az containerapp env create \
      --name $CONTAINERAPPS_ENVIRONMENT \
      --resource-group $RESOURCE_GROUP \
      --location $LOCATION
  set +e
fi

# Build JAR file and push to ACR using buildAcr profile
set -e
mvn clean package -DskipTests -PbuildAcr -DRESOURCE_GROUP=$RESOURCE_GROUP -DACR_NAME=$ACR_NAME
set +e

# Create the container app if not exists
az containerapp show -g $RESOURCE_GROUP -n $CONTAINERAPPS_NAME 1> /dev/null
if [ $? != 0 ]; then
  set -e
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
  set +e
fi

# create service connection.
az containerapp connection create postgres \
    --resource-group $RESOURCE_GROUP \
    --name $CONTAINERAPPS_NAME \
    --container $CONTAINERAPPS_CONTAINERNAME \
    --tg $RESOURCE_GROUP \
    --server $POSTGRESQL_HOST \
    --database $POSTGRESQL_DATABASE_NAME \
    --client-type java \
    --system-identity
