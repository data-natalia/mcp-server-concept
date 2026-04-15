using MCPServers.Shared;
using MCPServers.Shared.Services;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace {{ServerName}}.Services;

public class {{ServerName}}Service : BaseHttpService
{
    // Scope must end in /.default for MSAL OBO.
    // Examples: "https://org.crm4.dynamics.com/.default", "https://analysis.windows.net/powerbi/api/.default"
    private readonly string _scope;
    private readonly string _baseUrl;
    private readonly TokenContextAccessor _tokenContextAccessor;
    private readonly TokenExchangeService _tokenExchangeService;

    public {{ServerName}}Service(
        IConfiguration configuration,
        HttpClient client,
        ILogger<{{ServerName}}Service> logger,
        TokenContextAccessor tokenContextAccessor,
        TokenExchangeService tokenExchangeService)
        : base(configuration, client, logger)
    {
        _scope = configuration["DownstreamApi:Scope"]
            ?? throw new InvalidOperationException("DownstreamApi:Scope is not configured");
        _baseUrl = configuration["DownstreamApi:BaseUrl"]
            ?? throw new InvalidOperationException("DownstreamApi:BaseUrl is not configured");
        _tokenContextAccessor = tokenContextAccessor;
        _tokenExchangeService = tokenExchangeService;
    }

    public async Task<string> GetDataAsync(string input)
    {
        var tokenContext = _tokenContextAccessor.TokenValidatedContext;
        var accessToken = await _tokenExchangeService.ExchangeTokenAsync(tokenContext, _scope);

        _client.DefaultRequestHeaders.Remove("Authorization");
        _client.DefaultRequestHeaders.Add("Authorization", $"Bearer {accessToken}");

        var url = $"{_baseUrl}/TODO-replace-with-endpoint/{Uri.EscapeDataString(input)}";
        return await GetAsync(url);
    }
}
