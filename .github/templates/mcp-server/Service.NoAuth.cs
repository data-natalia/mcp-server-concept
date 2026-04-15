using MCPServers.Shared;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace {{ServerName}}.Services;

public class {{ServerName}}Service : BaseHttpService
{
    private readonly string _baseUrl;

    public {{ServerName}}Service(
        IConfiguration configuration,
        HttpClient client,
        ILogger<{{ServerName}}Service> logger)
        : base(configuration, client, logger)
    {
        _baseUrl = configuration["{{ApiConfigSection}}:BaseUrl"]
            ?? throw new InvalidOperationException("{{ApiConfigSection}}:BaseUrl is not configured");
    }

    public async Task<string> GetDataAsync(string input)
    {
        var url = $"{_baseUrl}/TODO-replace-with-endpoint/{Uri.EscapeDataString(input)}";
        return await GetAsync(url);
    }
}
