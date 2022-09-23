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
import javax.ws.rs.GET;
import javax.ws.rs.Path;
import javax.ws.rs.QueryParam;

import java.sql.Connection;
import java.sql.DriverManager;
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
    public String getServerTime() {
        Connection connection;

        try {
            Driver mySqlDriver = new Driver();
            // mySqlDriver.connect("jdbc:mysql://mysql-checklist-credential-free.mysql.database.azure.com:3306/checklist?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin&authenticationPlugins=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin&clientid=6f75da39-8c15-45a2-ba60-5bc2907c4048",
            // , Properties.)
            Properties info = new Properties();
            info.put("user", "checklistapp@microsoft.com@mysql-checklist-credential-free");
            connection = mySqlDriver.connect(
                    "jdbc:mysql://mysql-checklist-credential-free.mysql.database.azure.com:3306/checklist?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin&authenticationPlugins=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin&clientid=6f75da39-8c15-45a2-ba60-5bc2907c4048",
                    info);
            // connection = DriverManager.getConnection(
            // "jdbc:mysql://mysql-checklist-credential-free.mysql.database.azure.com:3306/checklist?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin&authenticationPlugins=com.azure.jdbc.msi.extension.mysql.AzureMySqlMSIAuthenticationPlugin&clientid=6f75da39-8c15-45a2-ba60-5bc2907c4048",
            // "checklistapp@microsoft.com@mysql-checklist-credential-free", null);

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