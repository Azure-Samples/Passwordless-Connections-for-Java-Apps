RESOURCE_GROUP=rg-spring-credential-free
POSTGRESQL_HOST=psql-spring-credential-free
DATABASE_NAME=checklist
DATABASE_FQDN=${POSTGRESQL_HOST}.postgres.database.azure.com
# Note that the connection url does not includes the password-free authentication plugin
# The configuration is injected by spring-cloud-azure-starter-jdbc
POSTGRESQL_CONNECTION_URL="jdbc:postgresql://${DATABASE_FQDN}:5432/${DATABASE_NAME}"
APPSERVICE_NAME=spring-credential-free
SPRING_APPS_SERVICE=credential-free-spring
LOCATION=eastus
POSTGRESQL_ADMIN_USER=azureuser
# Generating a random password for the PostgreSQL admin user as it is mandatory
# postgres admin won't be used as Azure AD authentication is leveraged also for administering the database
POSTGRESQL_ADMIN_PASSWORD=$(pwgen -s 15 1)

# Get current user logged in azure cli to make it postgres AAD admin
CURRENT_USER=$(az account show --query user.name -o tsv)
CURRENT_USER_OBJECTID=$(az ad user show --id $CURRENT_USER --query id -o tsv)

CURRENT_USER_DOMAIN=$(cut -d '@' -f2 <<< $CURRENT_USER)
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

# Create Spring App service
az spring create --name ${SPRING_APPS_SERVICE} \
    --resource-group ${RESOURCE_GROUP} \
    --location ${LOCATION} \
    --sku Basic

# Create Application
az spring app create --name ${APPSERVICE_NAME} \
    -s ${SPRING_APPS_SERVICE} \
    -g ${RESOURCE_GROUP} \
    --assign-endpoint true 

# create service connection.The service connection creates the managed identity if not exists.
az spring connection create postgres \
    --resource-group $RESOURCE_GROUP \
    --service $SPRING_APPS_SERVICE \
    --connection demo_connection \
    --app ${APPSERVICE_NAME} \
    --deployment default \
    --tg $RESOURCE_GROUP \
    --server $POSTGRESQL_HOST \
    --database $DATABASE_NAME \
    --client-type springboot


# Build JAR file
mvn clean package -DskipTests -f ../pom.xml

# Deploy application
az spring app deploy --name $APPSERVICE_NAME\
    --resource-group $RESOURCE_GROUP \
    --service $SPRING_APPS_SERVICE \
    --artifact-path ../target/app.jar
