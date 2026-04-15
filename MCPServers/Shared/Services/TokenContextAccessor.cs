using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Server;

namespace MCPServers.Shared.Services;

/// <summary>
/// Helper class to store and retrieve the TokenValidatedContext from the current HTTP request.
/// This allows services to access the validated token for token exchange scenarios.
/// </summary>
public class TokenContextAccessor
{
    private static readonly string TokenContextKey = "TokenValidatedContext";
    private readonly IHttpContextAccessor _httpContextAccessor;
    private readonly ILogger<TokenContextAccessor> _logger;

    public TokenContextAccessor(IHttpContextAccessor httpContextAccessor, ILogger<TokenContextAccessor> logger)
    {
        _httpContextAccessor = httpContextAccessor;
        _logger = logger;
    }

    /// <summary>
    /// Gets the current TokenValidatedContext from the HTTP context.
    /// </summary>
    public TokenValidatedContext? TokenValidatedContext
    {
        get
        {
            var httpContext = _httpContextAccessor.HttpContext;
            if (httpContext?.Items.TryGetValue(TokenContextKey, out var context) == true)
            {
                _logger.LogDebug("Retrieved TokenValidatedContext from HTTP context");
                return context as TokenValidatedContext;
            }
            _logger.LogWarning("TokenValidatedContext not found in HTTP context");
            return null;
        }
    }

    /// <summary>
    /// Sets the TokenValidatedContext in the HTTP context. Should be called from the OnTokenValidated event.
    /// </summary>
    public void SetTokenValidatedContext(TokenValidatedContext context)
    {
        var httpContext = _httpContextAccessor.HttpContext;
        if (httpContext != null)
        {
            httpContext.Items[TokenContextKey] = context;
            _logger.LogDebug("Set TokenValidatedContext in HTTP context");
        }
        else
        {
            _logger.LogWarning("HTTP context is null, cannot set TokenValidatedContext");
        }
    }

    /// <summary>
    /// Gets the incoming bearer token from the Authorization header.
    /// Used for token exchange scenarios (e.g., On-Behalf-Of flow).
    /// </summary>
    public string? GetIncomingBearerToken()
    {
        var httpContext = _httpContextAccessor.HttpContext;
        if (httpContext == null)
        {
            return null;
        }

        var authHeader = httpContext.Request.Headers["Authorization"].FirstOrDefault();
        if (authHeader?.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase) == true)
        {
            return authHeader.Substring("Bearer ".Length).Trim();
        }

        return null;
    }
}
