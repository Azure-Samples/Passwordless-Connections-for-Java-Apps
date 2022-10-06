# this deployment script assumes that a weblogic server was deployed in azure using the following template:
# https://portal.azure.com/#create/oracle.20191009-arm-oraclelinux-wls-admin20191009-arm-oraclelinux-wls-admin
# See https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/oracle/oracle-weblogic#oracle-weblogic-server-with-admin-server for more details
# It deploys a weblogic server and a weblogic admin server in the same VM.

# For simplicity, everything is deployed in the same resource group of the VM. The resource group should exist before running this script.
RESOURCE_GROUP=rg-wls-passwordless
# WLS server name that should be already deployed
VM_NAME=adminVM

APPLICATION_NAME=checklistapp

MYSQL_HOST=mysql-weblogic-passwordless
DATABASE_NAME=checklist
DATABASE_FQDN=${MYSQL_HOST}.mysql.database.azure.com
LOCATION=eastus
MYSQL_ADMIN_USER=azureuser
# Generating a random password for the MySQL user as it is mandatory
# mysql admin won't be used as Azure AD authentication is leveraged also for administering the database
MYSQL_ADMIN_PASSWORD=$(pwgen -s 15 1)

# User Managed Identity name for MySQL AAD authentication
MYSQL_UMI_NAME="id-mysql-aad"

# As the same server may host multiple application this sample will use user defined identitiy to be used by the application
# The datasource will be created in the application server and will be managed by the administrator, so the users cannot assign themselves other identities
# Be careful in production environments and don't let users to define their jdbc urls as they could use other applications' identities

# User assigned managed identity name for the application
APPLICATION_MSI_NAME="id-${APPLICATION_NAME}"
# Create user assignmed managed identity
az identity create -g $RESOURCE_GROUP -n $APPLICATION_MSI_NAME
# Assign the identity to the VM
az vm identity assign --resource-group $RESOURCE_GROUP --name $VM_NAME --identities $APPLICATION_MSI_NAME
# Get the identity id
az identity show -g $RESOURCE_GROUP -n $APPLICATION_MSI_NAME --query clientId -o tsv

# Get current user logged in azure cli to make it mysql AAD admin
CURRENT_USER=$(az account show --query user.name -o tsv)
CURRENT_USER_OBJECTID=$(az ad user show --id $CURRENT_USER --query id -o tsv)

APPLICATION_LOGIN_NAME=${APPLICATION_NAME}

# create mysql server
az mysql flexible-server create \
    --name $MYSQL_HOST \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --admin-user $MYSQL_ADMIN_USER \
    --admin-password $MYSQL_ADMIN_PASSWORD \
    --public-access 0.0.0.0 \
    --tier Burstable \
    --sku-name Standard_B1ms

# create User Managed Identity for MySQL to be used for AAD authentication
az identity create -g $RESOURCE_GROUP -n $MYSQL_UMI_NAME

## assign the identity to the MySQL server
az mysql flexible-server identity assign \
    --server-name $MYSQL_HOST \
    --resource-group $RESOURCE_GROUP \
    --identity $MYSQL_UMI_NAME

# create mysql server AAD admin user
az mysql flexible-server ad-admin create \
    --server-name $MYSQL_HOST \
    --resource-group $RESOURCE_GROUP \
    --object-id $CURRENT_USER_OBJECTID \
    --display-name $CURRENT_USER \
    --identity $MYSQL_UMI_NAME
# create mysql database
az mysql flexible-server db create \
    -g $RESOURCE_GROUP \
    -s $MYSQL_HOST \
    -d $DATABASE_NAME

# create service connection. Not supported VMs and managed identity
# Creating manually:
# 0. Create a temporary firewall rule to allow connections from current machine to the mysql server
MY_IP=$(curl http://whatismyip.akamai.com)
az mysql flexible-server firewall-rule create \
    --resource-group $RESOURCE_GROUP \
    --name $MYSQL_HOST \
    --rule-name AllowCurrentMachineToConnect \
    --start-ip-address ${MY_IP} \
    --end-ip-address ${MY_IP}

# 1. Get user defined managed clientId
APPLICATION_IDENTITY_APPID=$(az identity show -g ${RESOURCE_GROUP} -n ${APPLICATION_MSI_NAME} --query clientId -o tsv)
# 2. Create mysql user in the database and grant permissions the database. Note that login is performed using the current logged in user as AAD Admin and using an access token
RDBMS_ACCESS_TOKEN=$(az account get-access-token --resource-type oss-rdbms --output tsv --query accessToken)
mysql -h "${DATABASE_FQDN}" --user "${CURRENT_USER}" --enable-cleartext-plugin --password="$RDBMS_ACCESS_TOKEN" <<EOF
SET aad_auth_validate_oids_in_tenant = OFF;

DROP USER IF EXISTS '${APPLICATION_LOGIN_NAME}'@'%';

CREATE AADUSER '${APPLICATION_LOGIN_NAME}' IDENTIFIED BY '${APPLICATION_IDENTITY_APPID}';

GRANT ALL PRIVILEGES ON ${DATABASE_NAME}.* TO '${APPLICATION_LOGIN_NAME}'@'%';

FLUSH privileges;
EOF

# 3. Create Database tables
mysql -h "${DATABASE_FQDN}" --user "${CURRENT_USER}" --enable-cleartext-plugin --password="$RDBMS_ACCESS_TOKEN" <init-db.sql

# 4. Remove temporary firewall rule
az mysql flexible-server firewall-rule delete \
    --resource-group $RESOURCE_GROUP \
    --name $MYSQL_HOST \
    --rule-name AllowCurrentMachineToConnect \
    --yes

# End of service connection creation

# Build WAR file
mvn clean package -DskipTests -f ../pom.xml

# print the jdbc url to be used by the application
# Note that the connection url includes the password-free authentication plugin and the managed identity assigned to the VM.
MYSQL_CONNECTION_URL="jdbc:mysql://${DATABASE_FQDN}:3306/${DATABASE_NAME}?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.identity.providers.mysql.AzureIdentityMysqlAuthenticationPlugin&authenticationPlugins=com.azure.identity.providers.mysql.AzureIdentityMysqlAuthenticationPlugin&azure.clientId=${APPLICATION_IDENTITY_APPID}"
echo "Take note of the JDBC connection url to configure the datasource in WebLogic server"
echo "JDBC connection url: $MYSQL_CONNECTION_URL"
# Datasource configuration and application deployment should be done in the application server. Steps are explained in the README.md file.
