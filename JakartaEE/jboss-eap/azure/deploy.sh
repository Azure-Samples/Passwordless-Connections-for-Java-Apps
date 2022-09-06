POM_FILE='../pom.xml'
RESOURCE_GROUP=rg-jboss-credential-free
MYSQL_HOST=mysql-jboss-credential-free
DATABASE_NAME=checklist
DATABASE_FQDN=${MYSQL_HOST}.mysql.database.azure.com
# Note that the connection url includes the password-free authentication plugin
MYSQL_CONNECTION_URL="jdbc:mysql://${DATABASE_FQDN}:3306/${DATABASE_NAME}?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin&authenticationPlugins=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin"
APPSERVICE_NAME=jboss-credential-free
APPSERVICE_PLAN=asp-jboss-credential-free
LOCATION=eastus
MYSQL_ADMIN_USER=azureuser
# Generating a random password for the MySQL user as it is mandatory
# mysql admin won't be used as Azure AD authentication is leveraged also for administering the database
MYSQL_ADMIN_PASSWORD=$(pwgen -s 15 1)

# Get current user logged in azure cli to make it mysql AAD admin
CURRENT_USER=$(az account show --query user.name -o tsv)
CURRENT_USER_OBJECTID=$(az ad user show --id $CURRENT_USER --query id -o tsv)

CURRENT_USER_DOMAIN=$(cut -d '@' -f2 <<< $CURRENT_USER)
# APPSERVICE_LOGIN_NAME=${APPSERVICE_NAME}'@'${CURRENT_USER_DOMAIN}
APPSERVICE_LOGIN_NAME='checklistapp@'${CURRENT_USER_DOMAIN}

# create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# create mysql server
az mysql server create \
    --name $MYSQL_HOST \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --admin-user $MYSQL_ADMIN_USER \
    --admin-password $MYSQL_ADMIN_PASSWORD \
    --public-network-access 0.0.0.0 \
    --sku-name B_Gen5_1 
# create mysql server AAD admin user
az mysql server ad-admin create --server-name $MYSQL_HOST --resource-group $RESOURCE_GROUP --object-id $CURRENT_USER_OBJECTID --display-name $CURRENT_USER
# create mysql database
az mysql db create -g $RESOURCE_GROUP -s $MYSQL_HOST -n $DATABASE_NAME

# Create app service plan (premium required for JBoss EAP)
az appservice plan create --name $APPSERVICE_PLAN --resource-group $RESOURCE_GROUP --location $LOCATION --sku P1V3 --is-linux
# Create application service
az webapp create --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --plan $APPSERVICE_PLAN --runtime "JBOSSEAP:7-java8" --assign-identity [system]

# create service connection. Not yet supported for webapp and managed identity
# It would be something like: az webapp connection create mysql...
# So creating manually:
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

# 6. Build WAR file
mvn clean package -DskipTests -f ../pom.xml
# 7. Set environment variables for the web application pointing to the database and using the appservice identity login
az webapp config appsettings set -g $RESOURCE_GROUP -n $APPSERVICE_NAME --settings MYSQL_CONNECTION_URL=${MYSQL_CONNECTION_URL} MYSQL_USER=${APPSERVICE_LOGIN_NAME}'@'${MYSQL_HOST}
# 8. Create webapp deployment
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path ../target/ROOT.war --type war
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path ../src/main/webapp/WEB-INF/createMySQLDataSource.sh --type startup
