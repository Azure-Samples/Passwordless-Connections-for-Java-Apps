# this deployment script assumes that a websphere was deployed in azure using the following template:
# https://ms.portal.azure.com/#create/ibm-usa-ny-armonk-hq-6275750-ibmcloud-aiops.2022-01-07-twas-base-single-server2022-01-07-twas-base-single-server
# See https://learn.microsoft.com/en-us/azure/developer/java/ee/websphere-family for more details

# For simplicity, everything is deployed in the same resource group of the VM. The resource group should exist before running this script.
RESOURCE_GROUP=rg-websphere-passwordless
# websphere server name that should be already deployed
VM_NAME=wase01631-vm

APPLICATION_NAME=checklistapp

POSTGRESQL_HOST=postgres-websphere-passwordless
DATABASE_NAME=checklist
DATABASE_FQDN=${POSTGRESQL_HOST}.postgres.database.azure.com
LOCATION=eastus
POSTGRESQL_ADMIN_USER=azureuser
# Generating a random password for Posgresql admin user as it is mandatory
# postgresql admin won't be used as Azure AD authentication is leveraged also for administering the database
POSTGRESQL_ADMIN_PASSWORD=$(pwgen -s 15 1)

# As the same server may host multiple application this sample will use user defined identitiy to be used by the application
# The datasource will be created in the application server and will be managed by the administrator, so the users cannot assign themselves other identities
# Be careful in production environments and don't let users to define their jdbc urls as they could use other applications' identities

# User assigned managed identity name for the application
APPLICATION_MSI_NAME="id-${APPLICATION_NAME}"
# Create user assignmed managed identity
az identity create -g $RESOURCE_GROUP -n $APPLICATION_MSI_NAME
# # Assign the identity to the VM
az vm identity assign --resource-group $RESOURCE_GROUP --name $VM_NAME --identities $APPLICATION_MSI_NAME
# Get the identity id
az identity show -g $RESOURCE_GROUP -n $APPLICATION_MSI_NAME --query clientId -o tsv

# Get current user logged in azure cli to make it postgresql AAD admin
CURRENT_USER=$(az account show --query user.name -o tsv)
CURRENT_USER_OBJECTID=$(az ad user show --id $CURRENT_USER --query id -o tsv)

APPLICATION_LOGIN_NAME=checklistapp

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

# create postgres database
az postgres flexible-server db create \
    -g $RESOURCE_GROUP \
    -s $POSTGRESQL_HOST \
    -d $DATABASE_NAME

# before continue with next steps, please follow the instrucction in readme.md to configure an Azure AD admin for the database

# create service connection. Not supported VMs and managed identity
# Creating manually:
# 0. Create a temporary firewall rule to allow connections from current machine to the postgresql server
MY_IP=$(curl http://whatismyip.akamai.com)
az postgres flexible-server firewall-rule create \
    --resource-group $RESOURCE_GROUP \
    --name $POSTGRESQL_HOST \
    --rule-name AllowCurrentMachineToConnect \
    --start-ip-address ${MY_IP} \
    --end-ip-address ${MY_IP}

# 1. Get user defined managed clientId
APPLICATION_IDENTITY_APPID=$(az identity show -g ${RESOURCE_GROUP} -n ${APPLICATION_MSI_NAME} --query clientId -o tsv)

# 2. Note that login is performed using the current logged in user as AAD Admin and using an access token
export PGPASSWORD=$(az account get-access-token --resource-type oss-rdbms --output tsv --query accessToken)
# 3. Create Database tables
psql "host=$DATABASE_FQDN port=5432 user=${CURRENT_USER}@${POSTGRESQL_HOST} dbname=${DATABASE_NAME} sslmode=require" <init-db.sql

# 3. Create psql user in the database and grant permissions the database. Note that login is performed using the current logged in user as AAD Admin and using an access token
psql "host=$DATABASE_FQDN port=5432 user=${CURRENT_USER}@${POSTGRESQL_HOST} dbname=${DATABASE_NAME} sslmode=require" <<EOF
SET aad_validate_oids_in_tenant = off;

REVOKE ALL PRIVILEGES ON DATABASE "${DATABASE_NAME}" FROM "${APPLICATION_LOGIN_NAME}";

DROP USER IF EXISTS "${APPLICATION_LOGIN_NAME}";

CREATE ROLE "${APPLICATION_LOGIN_NAME}" WITH LOGIN PASSWORD '${APPLICATION_IDENTITY_APPID}' IN ROLE azure_ad_user;

GRANT ALL PRIVILEGES ON DATABASE "${DATABASE_NAME}" TO "${APPLICATION_LOGIN_NAME}";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "${APPLICATION_LOGIN_NAME}";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "${APPLICATION_LOGIN_NAME}";

EOF



# 4. Remove temporary firewall rule
az postgres server firewall-rule delete \
    --resource-group $RESOURCE_GROUP \
    --server $POSTGRESQL_HOST \
    --name AllowCurrentMachineToConnect

# End of service connection creation

# Build WAR file
mvn clean package -DskipTests -f ../pom.xml

# print the jdbc url to be used by the application
# Note that the connection url includes the password-free authentication plugin and the managed identity assigned to the VM.
POSTGRESQL_CONNECTION_URL="jdbc:postgresql://${DATABASE_FQDN}:5432/${DATABASE_NAME}?sslmode=require&authenticationPluginClassName=com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin&azure.clientId=${APPLICATION_IDENTITY_APPID}"
echo "Take note of the JDBC connection url to configure the datasource in websphere server"
echo "JDBC connection url: $POSTGRESQL_CONNECTION_URL"
# Datasource configuration and application deployment should be done in the application server. Steps are explained in the README.md file.
