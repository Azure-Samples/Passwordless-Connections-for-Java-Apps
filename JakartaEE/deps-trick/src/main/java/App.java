import com.azure.identity.providers.postgresql.AzureIdentityPostgresqlAuthenticationPlugin;

public class App {
    public static void main(String[] args) {
        AzureIdentityPostgresqlAuthenticationPlugin plugin = new AzureIdentityPostgresqlAuthenticationPlugin(null);
        System.out.println(plugin.getClass());
    }
}
