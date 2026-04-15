using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using ModelContextProtocol.AspNetCore.Authentication;
using System.Security.Claims;

namespace MCPServers.Shared.Extensions;

/// <summary>
/// Extension methods for configuring JWT Bearer and MCP authentication.
/// </summary>
public static class AuthenticationExtensions
{
    /// <summary>
    /// Adds standard MCP authentication with JWT Bearer tokens for Entra ID.
    /// </summary>
    /// <param name="services">The service collection</param>
    /// <param name="configuration">Configuration containing EntraIdAuth settings</param>
    /// <param name="onTokenValidated">Optional callback when token is validated</param>
    /// <param name="validateIssuer">Whether to validate the token issuer (default: true)</param>
    public static AuthenticationBuilder AddMcpAuthentication(
        this IServiceCollection services,
        IConfiguration configuration,
        Func<TokenValidatedContext, Task>? onTokenValidated = null,
        bool validateIssuer = true)
    {
        var tenantId = configuration["EntraIdAuth:TenantId"] 
            ?? throw new InvalidOperationException("EntraIdAuth:TenantId is not configured");
        var clientId = configuration["EntraIdAuth:ClientId"] 
            ?? throw new InvalidOperationException("EntraIdAuth:ClientId is not configured");
        
        var authority = $"https://login.microsoftonline.com/{tenantId}/v2.0";
        var audience = $"api://{clientId}";
        var publicUrl = configuration["EntraIdAuth:PublicUrl"] 
            ?? throw new InvalidOperationException("EntraIdAuth:PublicUrl is not configured");

        var loggerCategory = "Authentication.EntraIdAuth";

        ILogger GetAuthLogger(HttpContext httpContext)
        {
            var loggerFactory = httpContext.RequestServices.GetRequiredService<ILoggerFactory>();
            return loggerFactory.CreateLogger(loggerCategory);
        }

        return services.AddAuthentication(options =>
        {
            options.DefaultChallengeScheme = McpAuthenticationDefaults.AuthenticationScheme;
            options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
        })
        .AddJwtBearer(options =>
        {
            options.Authority = authority;
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = validateIssuer,
                ValidateAudience = true,
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                ValidIssuers = [authority, $"https://sts.windows.net/{tenantId}/"],
                ValidAudiences = [audience],
                NameClaimType = "name",
                RoleClaimType = "roles"
            };

            options.Events = new JwtBearerEvents
            {
                OnTokenValidated = context =>
                {
                    var name = context.Principal?.Identity?.Name ?? "unknown";
                    var email = context.Principal?.FindFirstValue("preferred_username") ?? "unknown";
                    var logger = GetAuthLogger(context.HttpContext);
                    logger.LogDebug("Token validated for: {Name} ({Email})", name, email);
                    
                    return onTokenValidated?.Invoke(context) ?? Task.CompletedTask;
                },
                OnAuthenticationFailed = context =>
                {
                    var logger = GetAuthLogger(context.HttpContext);
                    logger.LogWarning("Authentication failed: {Message}", context.Exception.Message);
                    return Task.CompletedTask;
                },
                OnChallenge = context =>
                {
                    var logger = GetAuthLogger(context.HttpContext);
                    logger.LogDebug("Challenging client to authenticate with Entra ID");
                    return Task.CompletedTask;
                }
            };
        })
        .AddMcp(options =>
        {
            options.ResourceMetadata = new()
            {
                Resource = publicUrl,
                AuthorizationServers = [authority],
                ScopesSupported = [$"{audience}/mcp.tools"],
            };
        });
    }
}
