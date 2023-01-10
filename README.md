# Passwordless Connections Samples for Java Apps

This project contains sample code for connecting to PostgreSQL and MySQL from the most popular Java frameworks and Azure hosting environments using Azure AD authentication with no need to manage passwords.

## Samples

This project provides the following samples for the following frameworks and Azure hosting environments:

* [SpringBoot](SpringBoot/README.md):
  * Azure Spring Apps.
  * Java SE on Azure App Service
  * Tomcat on Azure App Service
  * Azure Container Apps
* [Jakarta EE](JakartaEE/README.md):
  * JBoss EAP on Azure App Service.
  * WebLogic on Azure VM.
  * WebSphere on Azure VM.
* [Tomcat](Tomcat/README.md)
* [Quarkus](Quarkus/README.md):
  * Quarkus on Azure Container Apps.

## Getting Started

### Prerequisites

All samples are written in Java 8 and require the following;

- Java 8+.
- Maven
- Azure CLI 2.44+
- GIT
- An Azure subscription.
- PSQL or MYSQL client for some examples.
- pwgen (optional) for generating passwords in some examples.

The scripts delivered assume bash shell and were tested on Ubuntu 20.04 on WLS2. Other OSes may require some modifications or tools to be installed.
