RESOURCE_GROUP=rg-spring-springapp-passwordless
POSTGRESQL_HOST=psql-spring-springapp-passwordless
DATABASE_NAME=checklist
APPSERVICE_NAME=spring-springapp-passwordless
SPRING_APPS_SERVICE=passwordless-spring
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
az spring connection create postgres-flexible \
    --resource-group $RESOURCE_GROUP \
    --service $SPRING_APPS_SERVICE \
    --connection demo_connection \
    --app ${APPSERVICE_NAME} \
    --deployment default \
    --tg $RESOURCE_GROUP \
    --server $POSTGRESQL_HOST \
    --database $DATABASE_NAME \
    --system-identity \
    --client-type springboot


# Build JAR file
mvn clean package -DskipTests -f ../pom.xml

# Deploy application
az spring app deploy --name $APPSERVICE_NAME\
    --resource-group $RESOURCE_GROUP \
    --service $SPRING_APPS_SERVICE \
    --artifact-path ../target/app.jar \
    --env "SPRING_DATASOURCE_AZURE_PASSWORDLESSENABLED=true"
