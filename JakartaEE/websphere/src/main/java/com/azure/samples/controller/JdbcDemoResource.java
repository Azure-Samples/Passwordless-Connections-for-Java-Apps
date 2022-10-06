package com.azure.samples.controller;

import java.time.Duration;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Properties;

import javax.naming.Binding;
import javax.naming.Context;
import javax.naming.InitialContext;
import javax.naming.NamingEnumeration;
import javax.naming.NamingException;
import javax.sql.DataSource;
import javax.sql.PooledConnection;
import javax.ws.rs.GET;
import javax.ws.rs.Path;
import javax.ws.rs.QueryParam;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;

import com.azure.core.credential.AccessToken;
import com.azure.core.credential.TokenCredential;
import com.azure.core.credential.TokenRequestContext;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.mysql.cj.jdbc.Driver;

@Path("/jdbc")
public class JdbcDemoResource {

    @GET
    @Path("token")
    public String getAccessToken() {
        TokenCredential credential = new DefaultAzureCredentialBuilder().build();
        TokenRequestContext request = new TokenRequestContext();
        ArrayList<String> scopes = new ArrayList<>();
        scopes.add("https://ossrdbms-aad.database.windows.net");
        request.setScopes(scopes);
        AccessToken accessToken = credential.getToken(request).block(Duration.ofSeconds(30));
        return accessToken.getToken();
    }

    @GET
    @Path("umi")
    public String getAccessTokenUmi() {
        TokenCredential credential = new DefaultAzureCredentialBuilder()
                .managedIdentityClientId("83a9b025-6d22-42d3-8a71-530f40ad5d50")
                .build();
        TokenRequestContext request = new TokenRequestContext();
        ArrayList<String> scopes = new ArrayList<>();
        scopes.add("https://ossrdbms-aad.database.windows.net");
        request.setScopes(scopes);
        AccessToken accessToken = credential.getToken(request).block(Duration.ofSeconds(30));
        return accessToken.getToken();
    }

    @GET
    @Path("dsm")
    public String getServerTimeUmiM() {

        try {
            com.mysql.cj.jdbc.MysqlConnectionPoolDataSource ds = new com.mysql.cj.jdbc.MysqlConnectionPoolDataSource();
            ds.setUrl(
                    "jdbc:mysql://mysql-websphere-passwordless.mysql.database.azure.com:3306/checklist?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.identity.providers.mysql.AzureIdentityMysqlAuthenticationPlugin&authenticationPlugins=com.azure.identity.providers.mysql.AzureIdentityMysqlAuthenticationPlugin&azure.clientId=83a9b025-6d22-42d3-8a71-530f40ad5d50");
            ds.setUser("checklistapp");
            Connection connection = ds.createConnectionBuilder().build();
            if (connection != null) {
                System.out.println("Successfully connected.");
                System.out.println(connection.isValid(10));
                ResultSet result = connection.prepareStatement("SELECT now() as now").executeQuery();
                if (result.next()) {
                    return result.getString("now");
                }
            }
        } catch (SQLException e) {
            return "sql: " + e.getMessage();
        } catch (Exception e) {
            return "sql: " + e.getMessage();
        }
        return "no result?";
    }

    @GET
    @Path("dsp")
    public String getServerTimeUmiP() {

        try {
            org.postgresql.ds.PGConnectionPoolDataSource ds = new org.postgresql.ds.PGConnectionPoolDataSource();
            ds.setUrl(
                    "jdbc:postgresql://postgres-websphere-passwordless.postgres.database.azure.com:5432/checklist?sslmode=require&authenticationPluginClassName=com.azure.identity.providers.postgresql.AzureIdentityPostgresqlAuthenticationPlugin&azure.clientId=83a9b025-6d22-42d3-8a71-530f40ad5d50");
            ds.setUser("checklistapp@postgres-websphere-passwordless");
            PooledConnection connectionPooled = ds.getPooledConnection();
            if (connectionPooled != null) {
                Connection connection = connectionPooled.getConnection();
                if (connection != null) {
                    System.out.println("Successfully connected.");
                    System.out.println(connection.isValid(10));
                    ResultSet result = connection.prepareStatement("SELECT now() as now").executeQuery();
                    if (result.next()) {
                        return result.getString("now");
                    }
                }
            }
        } catch (SQLException e) {
            return "sql: " + e.getMessage();
        } catch (Exception e) {
            return "sql: " + e.getMessage();
        }
        return "no result?";
    }

    @GET
    public String getServerTime() {
        Connection connection;

        try {
            Driver mySqlDriver = new Driver();
            Properties info = new Properties();
            info.put("user", "checklistapp");
            connection = mySqlDriver.connect(
                    "jdbc:mysql://mysql-websphere-passwordless.mysql.database.azure.com:3306/checklist?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.identity.providers.mysql.AzureIdentityMysqlAuthenticationPlugin&authenticationPlugins=com.azure.identity.providers.mysql.AzureIdentityMysqlAuthenticationPlugin",
                    info);

            if (connection != null) {
                System.out.println("Successfully connected.");
                System.out.println(connection.isValid(10));
                ResultSet result = connection.prepareStatement("SELECT now() as now").executeQuery();
                if (result.next()) {
                    return result.getString("now");
                }
            }
        } catch (SQLException e) {
            return "new: " + e.getMessage();
        }
        return "no result?";
    }

    @GET
    @Path("jndi")
    public String getJndiResources(@QueryParam("jndiObject") String jndiObject) {
        try {
            String startLookup = (jndiObject == null) ? "" : jndiObject;
            InitialContext ictx = new InitialContext();
            Object ctx = (Object) ictx.lookup(startLookup);
            String result = "className: " + ctx.getClass().getName() + "\ntoString()=" + ctx.toString();
            if (ctx instanceof DataSource) {
                DataSource ds = (DataSource) ctx;
                ResultSet rs = ds.getConnection().prepareStatement("SELECT now() as now").executeQuery();
                if (rs.next()) {
                    return rs.getString("now");
                }
            }
            return result;
        } catch (SQLException sex) {
            return sex.getMessage();
        } catch (NamingException e) {
            // TODO Auto-generated catch block
            return e.getMessage();
        }

    }

    private String printContext(Context ctx, int indent) throws NamingException {
        NamingEnumeration en = ctx.listBindings("");
        StringBuilder result = new StringBuilder();
        while (en.hasMore()) {
            Binding b = (Binding) en.next();
            char[] tabs = new char[indent];
            Arrays.fill(tabs, '\t');
            result.append(result + new String(tabs) + b.getName() + " = " + b.getClassName() + "\n");
            if (b.getObject() instanceof Context) {
                result.append(printContext((Context) b.getObject(), indent + 1) + "\n");
            }
        }
        return result.toString();
    }
}