using Microsoft.Extensions.Configuration;

namespace MCPServers.Shared.Extensions;

/// <summary>
/// Extension methods for building configuration from standard sources.
/// </summary>
public static class ConfigurationExtensions
{
    /// <summary>
    /// Builds configuration from appsettings.json, appsettings.Development.json, and environment variables.
    /// This is the standard configuration pattern used across all MCP servers.
    /// </summary>
    public static IConfiguration BuildMcpConfiguration(bool includeEnvironmentVariables = false)
    {
        var builder = new ConfigurationBuilder()
            .SetBasePath(AppContext.BaseDirectory)
            .AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
            .AddJsonFile("appsettings.Development.json", optional: true, reloadOnChange: true)
            .AddJsonFile("appsettings.development.json", optional: true, reloadOnChange: true);

        if (includeEnvironmentVariables)
        {
            builder.AddEnvironmentVariables();
        }

        return builder.Build();
    }
}
