using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using MCPServers.Shared.Options;

namespace MCPServers.Shared.Services;

/// <summary>
/// Provides country code resolution from HTTP request headers or query parameters.
/// </summary>
public class CountryProvider
{
    private const string ContextItemKey = "McpCountryCode";

    private readonly IHttpContextAccessor _httpContextAccessor;
    private readonly ILogger<CountryProvider> _logger;
    private readonly IOptionsSnapshot<CountryProviderOptions> _options;

    public CountryProvider(
        IHttpContextAccessor httpContextAccessor,
        IOptionsSnapshot<CountryProviderOptions> options,
        ILogger<CountryProvider> logger)
    {
        _httpContextAccessor = httpContextAccessor ?? throw new ArgumentNullException(nameof(httpContextAccessor));
        _options = options ?? throw new ArgumentNullException(nameof(options));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    /// <summary>
    /// Gets the country code from the current HTTP request.
    /// Checks the configured header first, then falls back to query parameter.
    /// Returns the default country code if no valid country code is provided.
    /// </summary>
    public string GetCountryCode()
    {
        var options = _options.Value;
        var context = _httpContextAccessor.HttpContext;

        if (context == null)
        {
            _logger.LogWarning("No HTTP context available for country code resolution");
            return NormalizeCountryCode(options.DefaultCountryCode);
        }

        if (context.Items.TryGetValue(ContextItemKey, out var cached) && cached is string cachedCountry)
        {
            return cachedCountry;
        }

        var request = context.Request;
        string? countryCode = null;

        if (request.Headers.TryGetValue(options.HeaderName, out var headerValues))
        {
            countryCode = headerValues.FirstOrDefault();
            if (!string.IsNullOrWhiteSpace(countryCode))
            {
                _logger.LogDebug("Country code '{CountryCode}' found in header '{HeaderName}'", countryCode, options.HeaderName);
            }
        }

        if (string.IsNullOrWhiteSpace(countryCode) && request.Query.TryGetValue(options.QueryParameterName, out var queryValues))
        {
            countryCode = queryValues.FirstOrDefault();
            if (!string.IsNullOrWhiteSpace(countryCode))
            {
                _logger.LogDebug("Country code '{CountryCode}' found in query parameter '{QueryParameterName}'", countryCode, options.QueryParameterName);
            }
        }

        if (string.IsNullOrWhiteSpace(countryCode))
        {
            _logger.LogDebug("No country code provided, using default: {DefaultCountryCode}", options.DefaultCountryCode);
            countryCode = options.DefaultCountryCode;
        }

        var normalized = NormalizeCountryCode(countryCode.Trim());
        context.Items[ContextItemKey] = normalized;

        return normalized;
    }

    private static string NormalizeCountryCode(string countryCode) => countryCode.ToUpperInvariant();
}
