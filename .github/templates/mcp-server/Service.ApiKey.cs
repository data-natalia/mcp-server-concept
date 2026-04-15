using MCPServers.Shared;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace {{ServerName}}.Services;

public class {{ServerName}}Service : BaseHttpService
{
    private readonly string _baseUrl;
    private readonly string _apiKey;

    public {{ServerName}}Service(IConfiguration configuration, HttpClient client, ILogger<{{ServerName}}Service> logger)
        : base(configuration, client, logger)
    {
        _baseUrl = configuration["{{ApiConfigSection}}:BaseUrl"]
            ?? throw new InvalidOperationException("{{ApiConfigSection}}:BaseUrl is not configured");
        _apiKey = configuration["{{ApiConfigSection}}:ApiKey"]
            ?? throw new InvalidOperationException("{{ApiConfigSection}}:ApiKey is not configured");
    }

    public async Task<string> GetDataAsync(string input)
    {
        _client.DefaultRequestHeaders.Remove("X-Api-Key");
        _client.DefaultRequestHeaders.Add("X-Api-Key", _apiKey);

        var url = $"{_baseUrl}/TODO-replace-with-endpoint/{Uri.EscapeDataString(input)}";
        return await GetAsync(url);
    }
}
