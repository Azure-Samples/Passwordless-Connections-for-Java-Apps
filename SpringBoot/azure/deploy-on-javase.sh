RESOURCE_GROUP=rg-spring-javase-passwordless
POSTGRESQL_HOST=psql-spring-javase-passwordless
DATABASE_NAME=checklist
APPSERVICE_NAME=spring-javase-passwordless
APPSERVICE_PLAN=asp-spring-javase-passwordless
LOCATION=eastus
POSTGRESQL_ADMIN_USER=azureuser
# Generating a random password for the PostgreSQL admin user as it is mandatory
# postgres admin won't be used as Azure AD authentication is leveraged also for administering the database
POSTGRESQL_ADMIN_PASSWORD=$(pwgen -s 15 1)

# create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

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

# Create app service plan
az appservice plan create --name $APPSERVICE_PLAN --resource-group $RESOURCE_GROUP --location $LOCATION --sku B1 --is-linux
# Create application service
az webapp create --name $APPSERVICE_NAME --resource-group $RESOURCE_GROUP --plan $APPSERVICE_PLAN --runtime "JAVA:8-jre8"

# create service connection. 
az webapp connection create postgres-flexible \
    --resource-group $RESOURCE_GROUP \
    --name $APPSERVICE_NAME \
    --tg $RESOURCE_GROUP \
    --server $POSTGRESQL_HOST \
    --database $DATABASE_NAME \
    --client-type springboot \
    --system-identity 

# Build JAR file
mvn clean package -DskipTests -f ../pom.xml

# Set environment variables for the web application pointing to the database and using the appservice identity login
az webapp config appsettings set -g $RESOURCE_GROUP -n $APPSERVICE_NAME --settings "SPRING_DATASOURCE_AZURE_PASSWORDLESSENABLED=true"

# Create webapp deployment
az webapp deploy --resource-group $RESOURCE_GROUP --name $APPSERVICE_NAME --src-path ../target/app.jar --type jar
