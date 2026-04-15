using Microsoft.Extensions.Logging;

namespace MCPServers.Shared.Services;

/// <summary>
/// Null object implementation of IExportToStorageService that returns data unchanged.
/// Used when export functionality is not configured.
/// </summary>
public class NullExportToStorageService : IExportToStorageService
{
    private readonly ILogger<NullExportToStorageService> _logger;

    public NullExportToStorageService(ILogger<NullExportToStorageService> logger)
    {
        _logger = logger;
    }

    /// <inheritdoc />
    public Task<string> AddExportToResponseAsync(string jsonResponse, string toolName)
    {
        _logger.LogDebug("Export functionality not configured. Returning original JSON unchanged for tool {ToolName}", toolName);
        return Task.FromResult(jsonResponse);
    }
}
