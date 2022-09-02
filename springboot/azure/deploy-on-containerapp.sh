RESOURCE_GROUP=rg-spring-containerapp-credential-free
POSTGRESQL_HOST=psql-spring-containerapp-credential-free
DATABASE_NAME=checklist
DATABASE_FQDN=${POSTGRESQL_HOST}.postgres.database.azure.com
# Note that the connection url does not includes the password-free authentication plugin
# The configuration is injected by spring-cloud-azure-starter-jdbc

# CONTAINER APPS RELATED VARIABLES
ACR_NAME=credenialfreeacr
CONTAINERAPPS_ENVIRONMENT=acaenv-credential-free
CONTAINERAPPS_NAME=aca-credential-free

LOCATION=eastus
POSTGRESQL_ADMIN_USER=azureuser
# Generating a random password for the PostgreSQL admin user as it is mandatory
# postgres admin won't be used as Azure AD authentication is leveraged also for administering the database
POSTGRESQL_ADMIN_PASSWORD=$(pwgen -s 15 1)

# Get current user logged in azure cli to make it postgres AAD admin
CURRENT_USER=$(az account show --query user.name -o tsv)
CURRENT_USER_OBJECTID=$(az ad user show --id $CURRENT_USER --query id -o tsv)

CURRENT_USER_DOMAIN=$(cut -d '@' -f2 <<<$CURRENT_USER)
# APPSERVICE_LOGIN_NAME=${APPSERVICE_NAME}'@'${CURRENT_USER_DOMAIN}
APPSERVICE_LOGIN_NAME='checklistapp'

# create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# create postgresql server
az postgres server create \
    --name $POSTGRESQL_HOST \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --admin-user $POSTGRESQL_ADMIN_USER \
    --admin-password $POSTGRESQL_ADMIN_PASSWORD \
    --public-network-access 0.0.0.0 \
    --sku-name B_Gen5_1
# create postgres server AAD admin user
az postgres server ad-admin create --server-name $POSTGRESQL_HOST --resource-group $RESOURCE_GROUP --object-id $CURRENT_USER_OBJECTID --display-name $CURRENT_USER
# create postgres database
az postgres db create -g $RESOURCE_GROUP -s $POSTGRESQL_HOST -n $DATABASE_NAME

# create an Azure Container Registry (ACR) to hold the images for the demo
az acr create --resource-group $RESOURCE_GROUP --name $ACR_NAME --sku Standard --location $LOCATION --admin-enabled true

# register container apps extension
az extension add --name containerapp --upgrade
# register Microsoft.App namespace provider
az provider register --namespace Microsoft.App
# create an azure container app environment
az containerapp env create \
    --name $CONTAINERAPPS_ENVIRONMENT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION

# Create a user managed identity and assign AcrPull role on the ACR. By creating an user managed identity it is possible to assign AcrPull role before starting the deployment
# the same user manage identity is granted to access to the database
USER_IDENTITY=$(az identity create -g $RESOURCE_GROUP -n $CONTAINERAPPS_NAME --location $LOCATION --query clientId -o tsv)
ACR_RESOURCEID=$(az acr show --name $ACR_NAME --resource-group $RESOURCE_GROUP --query "id" --output tsv)
az role assignment create \
    --assignee "$USER_IDENTITY" --role AcrPull --scope "$ACR_RESOURCEID"

POSTGRESQL_CONNECTION_URL="jdbc:postgresql://${DATABASE_FQDN}:5432/${DATABASE_NAME}?clientid=${USER_IDENTITY}"

# create service connection. Not yet supported for containerapp and managed identity
# It would be something like: az containerapp connection create postgres...
# So creating manually:
# 0. Create a temporary firewall rule to allow connections from current machine to the postgres server
MY_IP=$(curl http://whatismyip.akamai.com)
az postgres server firewall-rule create --resource-group $RESOURCE_GROUP --server $POSTGRESQL_HOST --name AllowCurrentMachineToConnect --start-ip-address ${MY_IP} --end-ip-address ${MY_IP}
# 1. Create postgres user in the database and grant permissions the database. Note that login is performed using the current logged in user as AAD Admin and using an access token
export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --output tsv --query accessToken)
psql "host=$DATABASE_FQDN port=5432 user=${CURRENT_USER}@${POSTGRESQL_HOST} dbname=${DATABASE_NAME} sslmode=require" <<EOF
SET aad_validate_oids_in_tenant = off;

REVOKE ALL PRIVILEGES ON DATABASE "${DATABASE_NAME}" FROM "${APPSERVICE_LOGIN_NAME}";

DROP USER IF EXISTS "${APPSERVICE_LOGIN_NAME}";
DROP USER IF EXISTS "${APPSERVICE_LOGIN_NAME}@${CURRENT_USER_DOMAIN}";

CREATE ROLE "${APPSERVICE_LOGIN_NAME}" WITH LOGIN PASSWORD '${USER_IDENTITY}' IN ROLE azure_ad_user;

GRANT ALL PRIVILEGES ON DATABASE "${DATABASE_NAME}" TO "${APPSERVICE_LOGIN_NAME}";

EOF

# 2. Remove temporary firewall rule
az postgres server firewall-rule delete --resource-group $RESOURCE_GROUP --server $POSTGRESQL_HOST --name AllowCurrentMachineToConnect

# Service connection to postgresql end of configuration

# Build JAR file and push to ACR using buildAcr profile
mvn clean package -DskipTests -PbuildAcr -DRESOURCE_GROUP=$RESOURCE_GROUP -DACR_NAME=$ACR_NAME

# Create the container app
az containerapp create \
    --name ${CONTAINERAPPS_NAME} \
    --resource-group $RESOURCE_GROUP \
    --environment $CONTAINERAPPS_ENVIRONMENT \
    --container-name credential-free-container \
    --user-assigned ${CONTAINERAPPS_NAME} \
    --registry-server $ACR_NAME.azurecr.io \
    --image $ACR_NAME.azurecr.io/spring-credential-free:0.0.1-SNAPSHOT \
    --ingress external \
    --target-port 8080 \
    --cpu 1 \
    --memory 2 \
    --env-vars "SPRING_DATASOURCE_USERNAME=${APPSERVICE_LOGIN_NAME}@${POSTGRESQL_HOST}" "SPRING_DATASOURCE_URL=${POSTGRESQL_CONNECTION_URL}"
