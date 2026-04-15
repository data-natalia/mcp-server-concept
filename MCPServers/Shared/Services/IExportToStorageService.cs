namespace MCPServers.Shared.Services;

/// <summary>
/// Interface for exporting data to storage.
/// </summary>
public interface IExportToStorageService
{
    /// <summary>
    /// Exports JSON data containing an array to CSV and returns the original JSON augmented with an ExportUrl property.
    /// If parsing fails or no array is found, returns the original JSON unchanged.
    /// </summary>
    Task<string> AddExportToResponseAsync(string jsonResponse, string toolName);
}
