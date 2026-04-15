using MCPServers.Shared.Services;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace MCPServers.Shared.Extensions;

/// <summary>
/// Extension methods for registering ExportToStorageService in dependency injection.
/// </summary>
public static class ExportToStorageExtensions
{
    /// <summary>
    /// Adds the ExportToStorageService to the service collection.
    /// If connectionString is provided, registers the real Azure Blob Storage implementation.
    /// Otherwise, registers a null implementation that returns data unchanged.
    /// </summary>
    public static IServiceCollection AddExportToStorageService(this IServiceCollection services, string? connectionString = null)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            services.AddSingleton<IExportToStorageService, NullExportToStorageService>();
        }
        else
        {
            services.AddSingleton<IExportToStorageService>(sp =>
            {
                var logger = sp.GetRequiredService<ILogger<ExportToStorageService>>();
                return new ExportToStorageService(connectionString, logger);
            });
        }

        return services;
    }
}
