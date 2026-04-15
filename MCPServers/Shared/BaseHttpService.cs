using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace MCPServers.Shared;

/// <summary>
/// Base service class providing common HTTP operations and configuration access.
/// Inherit from this class to create domain-specific service classes.
/// </summary>
public abstract class BaseHttpService
{
    protected readonly IConfiguration _configuration;
    protected readonly HttpClient _client;
    protected readonly ILogger _logger;

    protected BaseHttpService(IConfiguration configuration, HttpClient client, ILogger logger)
    {
        _configuration = configuration ?? throw new ArgumentNullException(nameof(configuration));
        _client = client ?? throw new ArgumentNullException(nameof(client));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    /// <summary>
    /// Performs a GET request to the specified URL and returns the response content as a string.
    /// </summary>
    protected async Task<string> GetAsync(string url)
    {
        _logger.LogInformation("Sending GET request to {Url}", url);
        try
        {
            var response = await _client.GetAsync(url);
            response.EnsureSuccessStatusCode();
            var content = await response.Content.ReadAsStringAsync();
            _logger.LogInformation("Received successful response from {Url}", url);
            return content;
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "HTTP request failed for {Url}", url);
            throw;
        }
    }

    /// <summary>
    /// Performs a POST request to the specified URL with the given content and returns the response content as a string.
    /// </summary>
    protected async Task<string> PostAsync(string url, HttpContent content)
    {
        _logger.LogInformation("Sending POST request to {Url}", url);
        try
        {
            var response = await _client.PostAsync(url, content);
            response.EnsureSuccessStatusCode();
            var responseContent = await response.Content.ReadAsStringAsync();
            _logger.LogInformation("Received successful response from {Url}", url);
            return responseContent;
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "HTTP POST request failed for {Url}", url);
            throw;
        }
    }
}
