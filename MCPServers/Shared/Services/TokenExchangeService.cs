using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Identity.Client;
using ModelContextProtocol.Server;

namespace MCPServers.Shared.Services;

/// <summary>
/// Service for exchanging MCP authentication tokens for tokens to access other resources
/// using the On-Behalf-Of (OBO) flow.
/// </summary>
public class TokenExchangeService
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<TokenExchangeService> _logger;

    public TokenExchangeService(IConfiguration configuration, ILogger<TokenExchangeService> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    /// <summary>
    /// Exchanges the incoming MCP token for a token to access a different resource/audience.
    /// Uses the OAuth 2.0 On-Behalf-Of flow.
    /// </summary>
    /// <param name="tokenValidatedContext">The validated token context from MCP authentication</param>
    /// <param name="scope">The OAuth 2.0 scope to request — must end in <c>/.default</c> (e.g. <c>https://org.crm4.dynamics.com/.default</c>)</param>
    /// <returns>Access token for the requested scope, or null if the exchange fails</returns>
    public async Task<string?> ExchangeTokenAsync(
        TokenValidatedContext? tokenValidatedContext,
        string scope)
    {
        _logger.LogInformation("Attempting to acquire token for scope: {Scope}", scope);

        var incomingToken = tokenValidatedContext?.SecurityToken.UnsafeToString();
        if (string.IsNullOrEmpty(incomingToken))
        {
            _logger.LogWarning("Incoming token is null or empty.");
            return null;
        }

        var tenantId = _configuration["EntraIdAuth:TenantId"];
        var clientId = _configuration["EntraIdAuth:ClientId"];
        var clientSecret = _configuration["EntraIdAuth:ClientSecret"];

        if (string.IsNullOrEmpty(tenantId) || string.IsNullOrEmpty(clientId) || string.IsNullOrEmpty(clientSecret))
        {
            _logger.LogWarning("Configuration missing: EntraIdAuth:TenantId, EntraIdAuth:ClientId, or EntraIdAuth:ClientSecret");
            return null;
        }

        var authority = $"https://login.microsoftonline.com/{tenantId}";
        var cca = ConfidentialClientApplicationBuilder
            .Create(clientId)
            .WithClientSecret(clientSecret)
            .WithAuthority(authority)
            .Build();

        var userAssertion = new UserAssertion(incomingToken);
        try
        {
            var result = await cca.AcquireTokenOnBehalfOf(new[] { scope }, userAssertion).ExecuteAsync();
            _logger.LogInformation("Token acquired successfully for scope: {Scope}", scope);
            return result.AccessToken;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to acquire token for {Scope}: {Message}", scope, ex.Message);
            return null;
        }
    }

    /// <summary>
    /// Exchanges the incoming MCP token for a Power BI API token.
    /// </summary>
    public Task<string?> ExchangeForPowerBITokenAsync(TokenValidatedContext? tokenValidatedContext)
        => ExchangeTokenAsync(tokenValidatedContext, "https://analysis.windows.net/powerbi/api/.default");

    /// <summary>
    /// Exchanges the incoming MCP token for a Dynamics 365 token.
    /// </summary>
    /// <param name="tokenValidatedContext">The validated token context from MCP authentication</param>
    /// <param name="dynamicsBaseUrl">The Dynamics base URL (e.g., "https://org.crm4.dynamics.com")</param>
    public Task<string?> ExchangeForDynamicsTokenAsync(
        TokenValidatedContext? tokenValidatedContext,
        string dynamicsBaseUrl)
    {
        var scope = $"{dynamicsBaseUrl}/.default";
        return ExchangeTokenAsync(tokenValidatedContext, scope);
    }
}
