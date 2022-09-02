RESOURCE_GROUP=rg-tomcat-credential-free
POSTGRESQL_HOST=psql-tomcat-credential-free
DATABASE_NAME=checklist
DATABASE_FQDN=${POSTGRESQL_HOST}.postgres.database.azure.com
# Note that the connection url does not includes the password-free authentication plugin
# The configuration is injected by spring-cloud-azure-starter-jdbc
POSTGRESQL_CONNECTION_URL="jdbc:postgresql://${DATABASE_FQDN}:5432/${DATABASE_NAME}"
APPSERVICE_NAME=tomcat-credential-free
APPSERVICE_PLAN=asp-tomcat-credential-free
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



# Create app service plan
az appservice plan create --name $APPSERVICE_PLAN --resource-group $RESOURCE_GROUP --location $LOCATION --sku B1 --is-linux
# Create application service
az webapp create --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --plan $APPSERVICE_PLAN --runtime "TOMCAT:9.0-jre8" --assign-identity [system]

# create service connection. Not yet supported for webapp and managed identity
# It would be something like: az webapp connection create postgres...
# So creating manually:
# 0. Create a temporary firewall rule to allow connections from current machine to the postgres server
MY_IP=$(curl http://whatismyip.akamai.com)
az postgres server firewall-rule create --resource-group $RESOURCE_GROUP --server $POSTGRESQL_HOST --name AllowCurrentMachineToConnect --start-ip-address ${MY_IP} --end-ip-address ${MY_IP}
# 1. Get web application managed identity
APPSERVICE_IDENTITY_OBJID=$(az webapp show --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --query identity.principalId -o tsv)
# 2. IMPORTANT: It is required the clientId/appId, and previous command returns object id. So next step retrieve the client id
APPSERVICE_IDENTITY_APPID=$(az ad sp show --id $APPSERVICE_IDENTITY_OBJID --query appId -o tsv)
# 3. Create postgres user in the database and grant permissions the database. Note that login is performed using the current logged in user as AAD Admin and using an access token
export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --output tsv --query accessToken)
psql "host=$DATABASE_FQDN port=5432 user=${CURRENT_USER}@${POSTGRESQL_HOST} dbname=${DATABASE_NAME} sslmode=require" << EOF 
SET aad_validate_oids_in_tenant = off;

REVOKE ALL PRIVILEGES ON DATABASE "${DATABASE_NAME}" FROM "${APPSERVICE_LOGIN_NAME}";

DROP USER IF EXISTS "${APPSERVICE_LOGIN_NAME}";
DROP USER IF EXISTS "${APPSERVICE_LOGIN_NAME}@${CURRENT_USER_DOMAIN}";

CREATE ROLE "${APPSERVICE_LOGIN_NAME}" WITH LOGIN PASSWORD '${APPSERVICE_IDENTITY_APPID}' IN ROLE azure_ad_user;

GRANT ALL PRIVILEGES ON DATABASE "${DATABASE_NAME}" TO "${APPSERVICE_LOGIN_NAME}";

EOF

# 4. Remove temporary firewall rule
az postgres server firewall-rule delete --resource-group $RESOURCE_GROUP --server $POSTGRESQL_HOST --name AllowCurrentMachineToConnect

# Service connection to postgresql end of configuration

# Build WAR file
mvn clean package -DskipTests -f ../pom-war.xml

# 6. Set environment variables for the web application pointing to the database and using the appservice identity login
az webapp config appsettings set -g $RESOURCE_GROUP -n $APPSERVICE_NAME --settings "SPRING_DATASOURCE_USERNAME=${APPSERVICE_LOGIN_NAME}@${POSTGRESQL_HOST}" "SPRING_DATASOURCE_URL=${POSTGRESQL_CONNECTION_URL}"

# 7. Create webapp deployment
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path ../target/app.war --type war
