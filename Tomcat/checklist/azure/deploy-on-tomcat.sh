RESOURCE_GROUP=rg-tomcat-passwordless
POSTGRESQL_HOST=psql-tomcat-passwordless
DATABASE_NAME=checklist
APPSERVICE_NAME=tomcat-passwordless
APPSERVICE_PLAN=asp-tomcat-passwordless
LOCATION=eastus
POSTGRESQL_ADMIN_USER=azureuser
# Generating a random password for the PostgreSQL admin user as it is mandatory
# postgres admin won't be used as Azure AD authentication is leveraged also for administering the database
POSTGRESQL_ADMIN_PASSWORD=$(pwgen -s 15 1)
DATABASE_FQDN=${POSTGRESQL_HOST}.postgres.database.azure.com
PSQL_CONNECTION_URL="jdbc:postgresql://${DATABASE_FQDN}:5432/${DATABASE_NAME}?sslmode=require&authenticationPluginClassName=com.azure.identity.providers.postgresql.AzureIdentityPostgresqlAuthenticationPlugin"

CURRENT_USER=$(az account show --query user.name -o tsv)

# create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# create postgresql server
az postgres flexible-server create \
    --name $POSTGRESQL_HOST \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --admin-user $POSTGRESQL_ADMIN_USER \
    --admin-password $POSTGRESQL_ADMIN_PASSWORD \
    --public-access 0.0.0.0 \
    --tier Burstable \
    --sku-name Standard_B1ms \
    --storage-size 32 
# create postgres database
az postgres flexible-server db create -g $RESOURCE_GROUP -s $POSTGRESQL_HOST -d $DATABASE_NAME

# Create app service plan
az appservice plan create --name $APPSERVICE_PLAN --resource-group $RESOURCE_GROUP --location $LOCATION --sku B1 --is-linux
# Create application service
az webapp create --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --plan $APPSERVICE_PLAN --runtime "TOMCAT:10.0-java11"

# create service connection. 
az webapp connection create postgres-flexible \
    --resource-group $RESOURCE_GROUP \
    --name $APPSERVICE_NAME \
    --tg $RESOURCE_GROUP \
    --server $POSTGRESQL_HOST \
    --database $DATABASE_NAME \
    --client-type java \
    --system-identity

# # Create database schema. The service connector configured the current logged in user as Azure AD admin
# # create a firewall rule to allow access from the current IP address
# MY_IP=$(curl http://whatismyip.akamai.com)
# az postgres flexible-server firewall-rule create --resource-group $RESOURCE_GROUP --name $POSTGRESQL_HOST --rule-name AllowCurrentMachineToConnect --start-ip-address ${MY_IP} --end-ip-address ${MY_IP}

# # create db schema
# export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --output tsv --query accessToken)
# psql "host=$DATABASE_FQDN port=5432 user=${CURRENT_USER} dbname=${DATABASE_NAME} sslmode=require" < azure/create.sql

# # remove the firewall rule
# az postgres flexible-server firewall-rule delete --resource-group $RESOURCE_GROUP --name $POSTGRESQL_HOST --rule-name AllowCurrentMachineToConnect -y

# # Build WAR file
# mvn clean package

# Set connection url environment variables. It is necessary to pass it on CATALINA_OPTS environment variable
az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --settings 'CATALINA_OPTS=-DdbUrl="${AZURE_POSTGRESQL_CONNECTIONSTRING}&authenticationPluginClassName=com.azure.identity.providers.postgresql.AzureIdentityPostgresqlAuthenticationPlugin"'
# Create webapp deployment
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path target/app.war --type war


#######################################################################
az postgres flexible-server db delete -g $RESOURCE_GROUP -s $POSTGRESQL_HOST -d $DATABASE_NAME -y
az postgres flexible-server db create -g $RESOURCE_GROUP -s $POSTGRESQL_HOST -d $DATABASE_NAME
# create service connection. 
az webapp connection create postgres-flexible \
    --resource-group $RESOURCE_GROUP \
    --name $APPSERVICE_NAME \
    --tg $RESOURCE_GROUP \
    --server $POSTGRESQL_HOST \
    --database $DATABASE_NAME \
    --client-type java \
    --system-identity
az webapp config appsettings set --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --settings 'CATALINA_OPTS=-DdbUrl="${AZURE_POSTGRESQL_CONNECTIONSTRING}&authenticationPluginClassName=com.azure.identity.providers.postgresql.AzureIdentityPostgresqlAuthenticationPlugin"'
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path target/app.war --type war