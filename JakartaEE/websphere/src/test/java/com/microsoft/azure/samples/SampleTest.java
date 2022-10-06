package com.microsoft.azure.samples;

import org.junit.jupiter.api.Test;

import com.mysql.cj.jdbc.Driver;
import com.mysql.cj.jdbc.MysqlConnectionPoolDataSource;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Properties;

import javax.sql.PooledConnection;

public class SampleTest {

  @Test
  public void simpleJUnit5Test() {
    String result = "duke";
    assertEquals("duke", result);
  }

  @Test
  public void getServerTimeUmi() throws SQLException {

    MysqlConnectionPoolDataSource ds = new MysqlConnectionPoolDataSource();
    ds.setUrl(
        "jdbc:mysql://mysql-websphere-passwordless.mysql.database.azure.com:3306/checklist?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.identity.providers.mysql.AzureIdentityMysqlAuthenticationPlugin&authenticationPlugins=com.azure.identity.providers.mysql.AzureIdentityMysqlAuthenticationPlugin&azure.clientId=83a9b025-6d22-42d3-8a71-530f40ad5d50");
    ds.setUser("fmiguel@microsoft.com");
    ds.setConnectTimeout(60000);

    PooledConnection connectionPooled = ds.getPooledConnection();
    if (connectionPooled != null) {
      Connection connection = connectionPooled.getConnection();
      if (connection != null) {
        System.out.println("Successfully connected.");
        System.out.println(connection.isValid(10));
        ResultSet result = connection.prepareStatement("SELECT now() as now").executeQuery();
        if (result.next()) {
          assertNotNull(result.getString("now"));
        }

      }
    }
  }

  @Test
  public void getServerTime() throws SQLException {
    Connection connection;
    Driver mySqlDriver = new Driver();
    Properties info = new Properties();
    info.put("user", "fmiguel@microsoft.com");
    connection = mySqlDriver.connect(
        "jdbc:mysql://mysql-websphere-passwordless.mysql.database.azure.com:3306/checklist?useSSL=true&requireSSL=true&defaultAuthenticationPlugin=com.azure.identity.providers.mysql.AzureIdentityMysqlAuthenticationPlugin&authenticationPlugins=com.azure.identity.providers.mysql.AzureIdentityMysqlAuthenticationPlugin",
        info);

    if (connection != null) {
      System.out.println("Successfully connected.");
      System.out.println(connection.isValid(10));
      ResultSet result = connection.prepareStatement("SELECT now() as now").executeQuery();
      if (result.next()) {
        assertNotNull(result.getString("now"));
      }
    }
  }
}
