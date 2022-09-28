# Dependency helper

This project can be used to prepare the libraries required by WebLogic and WebSphere samples. It contains a pom.xml file with the required dependencies for the passwordless authentication plugin.

To download the libraries and its dependencies, run the following command:

```bash
mvn dependency:copy-dependencies
```

It downloads the dependencies to the `target/dependency` folder.

It also contains [prepare-pre.sh](./prepare-pre.sh) to generate the PRE_CLASSPATH value required. This script should be executed in target server with the appropriate paths.