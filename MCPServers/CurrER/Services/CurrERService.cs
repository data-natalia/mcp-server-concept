using MCPServers.Shared;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace CurrER.Services;

public class CurrERService : BaseHttpService
{
    private readonly string _baseUrl;
    private readonly string _dndBaseUrl;

    public CurrERService(
        IConfiguration configuration,
        HttpClient client,
        ILogger<CurrERService> logger)
        : base(configuration, client, logger)
    {
        _baseUrl = configuration["CurrERApi:BaseUrl"]
            ?? throw new InvalidOperationException("CurrERApi:BaseUrl is not configured");

        _dndBaseUrl = configuration["DndApi:BaseUrl"] ?? "https://www.dnd5eapi.co/api";
    }

    public async Task<string> GetDataAsync(string input)
    {
        var url = $"{_baseUrl}/TODO-replace-with-endpoint/{Uri.EscapeDataString(input)}";
        return await GetAsync(url);
    }

    public async Task<string> ListDndResourcesAsync(string category)
    {
        if (string.IsNullOrWhiteSpace(category))
        {
            throw new ArgumentException("Category must be provided.", nameof(category));
        }

        var normalizedCategory = category.Trim().ToLowerInvariant();
        var url = $"{_dndBaseUrl}/{Uri.EscapeDataString(normalizedCategory)}";
        return await GetAsync(url);
    }

    public async Task<string> GetDndResourceAsync(string category, string resourceName)
    {
        if (string.IsNullOrWhiteSpace(category))
        {
            throw new ArgumentException("Category must be provided.", nameof(category));
        }

        if (string.IsNullOrWhiteSpace(resourceName))
        {
            throw new ArgumentException("Resource name must be provided.", nameof(resourceName));
        }

        var normalizedCategory = category.Trim().ToLowerInvariant();
        var normalizedResourceName = resourceName.Trim().ToLowerInvariant();
        var url = $"{_dndBaseUrl}/{Uri.EscapeDataString(normalizedCategory)}/{Uri.EscapeDataString(normalizedResourceName)}";
        return await GetAsync(url);
    }
}
