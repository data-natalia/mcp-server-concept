using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using MCPServers.Shared.Options;
using MCPServers.Shared.Services;

namespace MCPServers.Shared.Extensions;

/// <summary>
/// Extension methods for configuring the country provider service.
/// </summary>
public static class CountryProviderExtensions
{
    /// <summary>
    /// Adds the country provider service to the service collection.
    /// Requires AddHttpContextAccessor() to be called before this method.
    /// </summary>
    public static IServiceCollection AddCountryProvider(
        this IServiceCollection services,
        Action<CountryProviderOptions>? configure = null)
    {
        ArgumentNullException.ThrowIfNull(services);

        services.AddHttpContextAccessor();

        if (configure != null)
        {
            services.Configure(configure);
        }
        else
        {
            services.Configure<CountryProviderOptions>(_ => { });
        }

        services.TryAddScoped<CountryProvider>();

        return services;
    }

    /// <summary>
    /// Adds the country provider service with a default country code.
    /// </summary>
    public static IServiceCollection AddDefaultCountryProvider(
        this IServiceCollection services,
        string defaultCountryCode = "NO")
    {
        return services.AddCountryProvider(options =>
        {
            options.DefaultCountryCode = defaultCountryCode;
        });
    }
}
