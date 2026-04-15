using System.Reflection;
using System.Text;
using System.Text.Json;
using Azure.Storage.Blobs;
using Azure.Storage.Sas;
using Microsoft.Extensions.Logging;

namespace MCPServers.Shared.Services;

/// <summary>
/// Service for exporting data to Azure Blob Storage.
/// </summary>
public class ExportToStorageService : IExportToStorageService
{
    #region Constants

    private const string ContainerName = "toolexports";
    private const int SasTokenExpirationMinutes = 15;
    private const int MaxJsonSearchDepth = 4;
    private const int MinItemsForExport = 10;
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };

    #endregion

    #region Fields

    private readonly BlobServiceClient _blobServiceClient;
    private readonly ILogger<ExportToStorageService> _logger;

    #endregion

    #region Constructor

    /// <summary>
    /// Initializes a new instance of the <see cref="ExportToStorageService"/> class.
    /// </summary>
    /// <param name="connectionString">The Azure Storage account connection string.</param>
    /// <param name="logger">The logger instance.</param>
    public ExportToStorageService(string connectionString, ILogger<ExportToStorageService> logger)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString, nameof(connectionString));
        
        _blobServiceClient = new BlobServiceClient(connectionString);
        _logger = logger;
    }

    #endregion

    #region Public Methods

    /// <summary>
    /// Exports JSON data containing an array to CSV and returns the original JSON augmented with an ExportUrl property.
    /// If parsing fails or no array is found, returns the original JSON unchanged.
    /// </summary>
    /// <param name="jsonResponse">The JSON response string that may contain an array at any nesting level.</param>
    /// <param name="toolName">The name of the tool, used as a folder path in the container.</param>
    /// <returns>The original JSON with ExportUrl added at root level, or the original JSON unchanged if export fails.</returns>
    public async Task<string> AddExportToResponseAsync(string jsonResponse, string toolName)
    {
        _logger.LogInformation("Starting export process for tool {ToolName}", toolName);

        if (string.IsNullOrWhiteSpace(jsonResponse))
        {
            _logger.LogDebug("JSON response is null or whitespace for tool {ToolName}, returning unchanged", toolName);
            return jsonResponse;
        }

        ArgumentException.ThrowIfNullOrWhiteSpace(toolName, nameof(toolName));

        try
        {
            _logger.LogDebug("Parsing JSON response for tool {ToolName}", toolName);
            // Parse the JSON
            using var document = JsonDocument.Parse(jsonResponse);
            var root = document.RootElement;

            _logger.LogDebug("Searching for array in JSON structure for tool {ToolName}", toolName);
            // Find the first array in the JSON structure
            if (!TryFindFirstArray(root, out var arrayElement) || arrayElement.GetArrayLength() <= MinItemsForExport)
            {
                var arrayLength = arrayElement.ValueKind == JsonValueKind.Array ? arrayElement.GetArrayLength() : 0;
                _logger.LogInformation("No array with more than {MinItems} items found in JSON response for tool {ToolName}. Array length: {ArrayLength}", 
                    MinItemsForExport, toolName, arrayLength);
                return jsonResponse;
            }

            _logger.LogInformation("Found array with {ItemCount} items for tool {ToolName}, proceeding with CSV conversion", arrayElement.GetArrayLength(), toolName);
            // Convert array to CSV
            var csvContent = ConvertJsonArrayToCsv(arrayElement);
            if (string.IsNullOrEmpty(csvContent))
            {
                _logger.LogWarning("CSV conversion resulted in empty content for tool {ToolName}", toolName);
                return jsonResponse;
            }

            _logger.LogDebug("CSV conversion successful for tool {ToolName}, content length: {Length} characters", toolName, csvContent.Length);
            // Upload to blob storage
            var exportUrl = await UploadCsvToBlobAsync(csvContent, toolName);

            _logger.LogInformation("Successfully uploaded CSV for tool {ToolName}, export URL: {ExportUrl}", toolName, exportUrl);
            // Augment the original JSON with the export URL
            var augmentedJson = AugmentJsonWithExportUrl(root, exportUrl);
            _logger.LogInformation("Augmented JSON with export URL for tool {ToolName}", toolName);
            return augmentedJson;
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Failed to parse JSON response for export in tool {ToolName}", toolName);
            return jsonResponse;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to export JSON to CSV for tool {ToolName}", toolName);
            return jsonResponse;
        }
    }

    /// <summary>
    /// Exports a list of items to a CSV file in Azure Blob Storage and returns a SAS URL valid for 15 minutes.
    /// </summary>
    /// <typeparam name="T">The type of items in the list.</typeparam>
    /// <param name="data">The data to export.</param>
    /// <param name="toolName">The name of the tool, used as a folder path in the container.</param>
    /// <returns>A SAS URL to access the uploaded CSV file, valid for 15 minutes.</returns>
    [Obsolete("Use ExportJsonToCsvAndAugmentAsync for JSON-based export. This method will be removed in a future version.")]
    public async Task<string> ExportToCsvAsync<T>(IEnumerable<T> data, string toolName)
    {
        ArgumentNullException.ThrowIfNull(data, nameof(data));
        ArgumentException.ThrowIfNullOrWhiteSpace(toolName, nameof(toolName));

        var csvContent = ConvertTypedToCsv(data);
        return await UploadCsvToBlobAsync(csvContent, toolName);
    }

    #endregion

    #region Private Methods - Array Finding

    /// <summary>
    /// Recursively searches for the first non-empty array in the JSON structure (depth-first).
    /// </summary>
    private static bool TryFindFirstArray(JsonElement element, out JsonElement array)
    {
        return TryFindFirstArray(element, out array, 0);
    }

    /// <summary>
    /// Recursively searches for the first non-empty array in the JSON structure (depth-first) with depth limiting.
    /// </summary>
    private static bool TryFindFirstArray(JsonElement element, out JsonElement array, int currentDepth)
    {
        array = default;

        // Prevent stack overflow from deeply nested JSON
        if (currentDepth >= MaxJsonSearchDepth)
        {
            return false;
        }

        switch (element.ValueKind)
        {
            case JsonValueKind.Array:
                if (element.GetArrayLength() > 0)
                {
                    array = element;
                    return true;
                }
                return false;

            case JsonValueKind.Object:
                foreach (var property in element.EnumerateObject())
                {
                    if (TryFindFirstArray(property.Value, out array, currentDepth + 1))
                    {
                        return true;
                    }
                }
                return false;

            default:
                return false;
        }
    }

    #endregion

    #region Private Methods - CSV Conversion

    /// <summary>
    /// Converts a JSON array to CSV format. Nested objects/arrays are serialized as JSON strings.
    /// </summary>
    private string ConvertJsonArrayToCsv(JsonElement array)
    {
        var items = array.EnumerateArray().ToList();
        if (items.Count == 0)
        {
            _logger.LogDebug("Array is empty, returning empty CSV");
            return string.Empty;
        }

        _logger.LogDebug("Converting array with {ItemCount} items to CSV", items.Count);
        // Collect all unique property names from all items (in case items have different properties)
        var allHeaders = new LinkedHashSet<string>();
        foreach (var item in items)
        {
            if (item.ValueKind == JsonValueKind.Object)
            {
                foreach (var prop in item.EnumerateObject())
                {
                    allHeaders.Add(prop.Name);
                }
            }
        }

        if (allHeaders.Count == 0)
        {
            // Array contains non-object items (primitives), create single "Value" column
            _logger.LogDebug("Array contains primitives, using single 'Value' column");
            allHeaders.Add("Value");
        }
        else
        {
            _logger.LogDebug("Found {HeaderCount} unique headers: {Headers}", allHeaders.Count, string.Join(", ", allHeaders));
        }

        var sb = new StringBuilder();
        var headerList = allHeaders.ToList();

        // Write header row
        var headerRow = string.Join(",", headerList.Select(EscapeCsvValue));
        sb.AppendLine(headerRow);
        _logger.LogDebug("Wrote header row: {HeaderRow}", headerRow);

        // Write data rows
        int rowCount = 0;
        foreach (var item in items)
        {
            if (item.ValueKind == JsonValueKind.Object)
            {
                var values = headerList.Select(header =>
                {
                    if (item.TryGetProperty(header, out var propValue))
                    {
                        return GetCsvValueFromJsonElement(propValue);
                    }
                    return string.Empty;
                });
                var row = string.Join(",", values);
                sb.AppendLine(row);
            }
            else
            {
                // Handle array of primitives
                var row = GetCsvValueFromJsonElement(item);
                sb.AppendLine(row);
            }
            rowCount++;
        }

        _logger.LogDebug("Wrote {RowCount} data rows", rowCount);
        var csv = sb.ToString();
        _logger.LogDebug("CSV conversion complete, total length: {Length} characters", csv.Length);
        return csv;
    }

    /// <summary>
    /// Gets a CSV-safe string value from a JsonElement.
    /// Objects and arrays are serialized as JSON strings.
    /// </summary>
    private static string GetCsvValueFromJsonElement(JsonElement element)
    {
        return element.ValueKind switch
        {
            JsonValueKind.String => EscapeCsvValue(element.GetString() ?? string.Empty),
            JsonValueKind.Number => EscapeCsvValue(element.GetRawText()),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            JsonValueKind.Null => string.Empty,
            JsonValueKind.Object or JsonValueKind.Array => EscapeCsvValue(element.GetRawText()),
            _ => string.Empty
        };
    }

    /// <summary>
    /// Converts a typed enumerable to CSV format.
    /// </summary>
    private static string ConvertTypedToCsv<T>(IEnumerable<T> data)
    {
        var dataList = data.ToList();
        if (dataList.Count == 0)
        {
            return string.Empty;
        }

        var sb = new StringBuilder();
        var properties = typeof(T).GetProperties(BindingFlags.Public | BindingFlags.Instance);

        // Write header row
        var headers = properties.Select(p => EscapeCsvValue(p.Name));
        sb.AppendLine(string.Join(",", headers));

        // Write data rows
        foreach (var item in dataList)
        {
            var values = properties.Select(p =>
            {
                var value = p.GetValue(item);
                return EscapeCsvValue(value?.ToString() ?? string.Empty);
            });
            sb.AppendLine(string.Join(",", values));
        }

        return sb.ToString();
    }

    /// <summary>
    /// Escapes a value for CSV format.
    /// </summary>
    private static string EscapeCsvValue(string value)
    {
        if (string.IsNullOrEmpty(value))
        {
            return string.Empty;
        }

        // If value contains comma, quote, or newline, wrap in quotes and escape existing quotes
        if (value.Contains(',') || value.Contains('"') || value.Contains('\n') || value.Contains('\r'))
        {
            return $"\"{value.Replace("\"", "\"\"")}\"";
        }

        return value;
    }

    #endregion

    #region Private Methods - Blob Storage

    /// <summary>
    /// Uploads CSV content to blob storage and returns a SAS URL.
    /// </summary>
    private async Task<string> UploadCsvToBlobAsync(string csvContent, string toolName)
    {
        var blobName = $"{toolName}/{Guid.NewGuid()}.csv";

        _logger.LogInformation("Exporting data to CSV blob: {ContainerName}/{BlobName}", ContainerName, blobName);

        var containerClient = _blobServiceClient.GetBlobContainerClient(ContainerName);
        _logger.LogDebug("Ensuring container {ContainerName} exists", ContainerName);
        await containerClient.CreateIfNotExistsAsync();
        _logger.LogDebug("Container {ContainerName} is ready", ContainerName);

        var blobClient = containerClient.GetBlobClient(blobName);
        _logger.LogDebug("Starting upload of {ByteCount} bytes to blob {BlobName}", Encoding.UTF8.GetByteCount(csvContent), blobName);
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(csvContent));
        await blobClient.UploadAsync(stream, overwrite: true);
        _logger.LogDebug("Upload completed for blob {BlobName}", blobName);

        _logger.LogDebug("Generating SAS URI for blob {BlobName}", blobName);
        var sasUri = GenerateSasUri(blobClient);

        _logger.LogInformation("Successfully exported CSV to {BlobName} with SAS token expiring in {Minutes} minutes",
            blobName, SasTokenExpirationMinutes);

        return sasUri;
    }

    /// <summary>
    /// Generates a SAS URI for the blob with read permissions.
    /// </summary>
    private static string GenerateSasUri(BlobClient blobClient)
    {
        var sasBuilder = new BlobSasBuilder
        {
            BlobContainerName = blobClient.BlobContainerName,
            BlobName = blobClient.Name,
            Resource = "b", // b = blob
            ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(SasTokenExpirationMinutes)
        };

        sasBuilder.SetPermissions(BlobSasPermissions.Read);

        var sasUri = blobClient.GenerateSasUri(sasBuilder);
        return sasUri.ToString();
    }

    #endregion

    #region Private Methods - JSON Augmentation

    /// <summary>
    /// Adds an ExportUrl property to the root of the JSON response.
    /// </summary>
    private static string AugmentJsonWithExportUrl(JsonElement originalRoot, string exportUrl)
    {
        var result = new Dictionary<string, object>
        {
            ["ExportUrl"] = exportUrl
        };

        // Copy all original properties if root is an object
        if (originalRoot.ValueKind == JsonValueKind.Object)
        {
            foreach (var property in originalRoot.EnumerateObject())
            {
                result[property.Name] = JsonSerializer.Deserialize<object>(property.Value.GetRawText())!;
            }
        }
        else
        {
            // If root is an array or primitive, wrap it in a "Data" property
            result["Data"] = JsonSerializer.Deserialize<object>(originalRoot.GetRawText())!;
        }

        return JsonSerializer.Serialize(result, JsonOptions);
    }

    #endregion

    #region Helper Classes

    /// <summary>
    /// A HashSet that maintains insertion order.
    /// </summary>
    private class LinkedHashSet<T> : IEnumerable<T> where T : notnull
    {
        private readonly Dictionary<T, LinkedListNode<T>> _dict = new();
        private readonly LinkedList<T> _list = new();

        public bool Add(T item)
        {
            if (_dict.ContainsKey(item))
            {
                return false;
            }
            var node = _list.AddLast(item);
            _dict[item] = node;
            return true;
        }

        public int Count => _dict.Count;

        public List<T> ToList() => _list.ToList();

        public IEnumerator<T> GetEnumerator() => _list.GetEnumerator();

        System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator() => GetEnumerator();
    }

    #endregion
}
