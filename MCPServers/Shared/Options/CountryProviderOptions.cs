namespace MCPServers.Shared.Options;

/// <summary>
/// Configuration options for the country provider service.
/// </summary>
public class CountryProviderOptions
{
    /// <summary>
    /// The default country code to use when no country is specified or the header value is empty.
    /// </summary>
    public string DefaultCountryCode { get; set; } = "NO";

    /// <summary>
    /// The HTTP header name to read the country code from.
    /// Default: x-mcp-country
    /// </summary>
    public string HeaderName { get; set; } = "x-mcp-country";

    /// <summary>
    /// The query parameter name to read the country code from as fallback.
    /// Default: country
    /// </summary>
    public string QueryParameterName { get; set; } = "country";
}
