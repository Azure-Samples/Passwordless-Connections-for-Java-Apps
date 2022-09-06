POM_FILE='../pom.xml'
RESOURCE_GROUP=rg-jboss-passwordless
MYSQL_HOST=mysql-jboss-passwordless
DATABASE_NAME=checklist
DATABASE_FQDN=${MYSQL_HOST}.mysql.database.azure.com
# Note that the connection url includes the password-free authentication plugin
MYSQL_CONNECTION_URL="jdbc:mysql://${DATABASE_FQDN}:3306/${DATABASE_NAME}?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin&authenticationPlugins=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin"
APPSERVICE_NAME=jboss-passwordless
APPSERVICE_PLAN=asp-jboss-passwordless
LOCATION=eastus
MYSQL_ADMIN_USER=azureuser
# Generating a random password for the MySQL user as it is mandatory
# mysql admin won't be used as Azure AD authentication is leveraged also for administering the database
MYSQL_ADMIN_PASSWORD=$(pwgen -s 15 1)

# # Get current user logged in azure cli to make it mysql AAD admin
CURRENT_USER=$(az account show --query user.name -o tsv)
CURRENT_USER_OBJECTID=$(az ad user show --id $CURRENT_USER --query id -o tsv)

# CURRENT_USER_DOMAIN=$(cut -d '@' -f2 <<< $CURRENT_USER)
# # APPSERVICE_LOGIN_NAME=${APPSERVICE_NAME}'@'${CURRENT_USER_DOMAIN}
# APPSERVICE_LOGIN_NAME='checklistapp@'${CURRENT_USER_DOMAIN}

# create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# create mysql server
az mysql flexible-server create \
    --name $MYSQL_HOST \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --admin-user $MYSQL_ADMIN_USER \
    --admin-password $MYSQL_ADMIN_PASSWORD \
    --public-access 0.0.0.0 \
    --tier Burstable \
    --sku-name Standard_B1ms \
    --storage-size 32 

# create mysql database
az mysql flexible-server db create -g $RESOURCE_GROUP -s $MYSQL_HOST -d $DATABASE_NAME

# Create app service plan (premium required for JBoss EAP)
az appservice plan create --name $APPSERVICE_PLAN --resource-group $RESOURCE_GROUP --location $LOCATION --sku P1V3 --is-linux
# Create application service
az webapp create --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --plan $APPSERVICE_PLAN --runtime "JBOSSEAP:7-java8"

# create service connection. 
az webapp connection create mysql-flexible \
    --resource-group $RESOURCE_GROUP \
    --name $APPSERVICE_NAME \
    --tg $RESOURCE_GROUP \
    --server $MYSQL_HOST \
    --database $DATABASE_NAME \
    --client-type java \
    --system-identity 

# POPULATE DATABASE
# 0. Create a temporary firewall rule to allow connections from current machine to the mysql server
MY_IP=$(curl http://whatismyip.akamai.com)
az mysql flexible-server firewall-rule create --resource-group $RESOURCE_GROUP --server $MYSQL_HOST --name AllowCurrentMachineToConnect --start-ip-address ${MY_IP} --end-ip-address ${MY_IP}

# 1. Create Database tables
RDBMS_ACCESS_TOKEN=$(az account get-access-token --resource-type oss-rdbms --output tsv --query accessToken)
mysql -h "${DATABASE_FQDN}" --user "${CURRENT_USER}@${MYSQL_HOST}" --enable-cleartext-plugin --password="$RDBMS_ACCESS_TOKEN" < init-db.sql

# 2. Remove temporary firewall rule
az mysql flexible-server firewall-rule delete --resource-group $RESOURCE_GROUP --server $MYSQL_HOST --name AllowCurrentMachineToConnect

# Build WAR file
mvn clean package -DskipTests -f ../pom.xml
# Set environment variables for the web application pointing to the database and using the appservice identity login
# az webapp config appsettings set -g $RESOURCE_GROUP -n $APPSERVICE_NAME --settings MYSQL_CONNECTION_URL=${MYSQL_CONNECTION_URL} MYSQL_USER=${APPSERVICE_LOGIN_NAME}'@'${MYSQL_HOST}
# Create webapp deployment
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path ../target/ROOT.war --type war
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path ../src/main/webapp/WEB-INF/createMySQLDataSource.sh --type startup
