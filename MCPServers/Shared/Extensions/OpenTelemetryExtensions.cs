using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using OpenTelemetry;

namespace MCPServers.Shared.Extensions;

/// <summary>
/// Extension methods for configuring OpenTelemetry with Azure Monitor.
/// </summary>
public static class OpenTelemetryExtensions
{
    /// <summary>
    /// Adds OpenTelemetry with Azure Monitor if Application Insights connection string is configured.
    /// Also configures OpenTelemetry logging with standard options.
    /// </summary>
    public static IServiceCollection AddMcpOpenTelemetry(this IServiceCollection services, ILoggingBuilder loggingBuilder)
    {
        var openTelemetryBuilder = services.AddOpenTelemetry();
        
        if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING")))
        {
            openTelemetryBuilder.UseAzureMonitor();
        }

        // Configure logging to use OpenTelemetry
        loggingBuilder.AddOpenTelemetry(options =>
        {
            options.IncludeScopes = true;
            options.ParseStateValues = true;
            options.IncludeFormattedMessage = true;
        });

        return services;
    }
}
