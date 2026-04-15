using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;

namespace MCPServers.Shared.Services;

/// <summary>
/// Helper class for Azure Blob Storage operations.
/// </summary>
public static class BlobStorageHelper
{
    private const int DefaultSasTokenExpirationMinutes = 60;

    /// <summary>
    /// Generates a SAS URI for a blob with read permissions.
    /// </summary>
    /// <param name="blobClient">The blob client for which to generate the SAS URI.</param>
    /// <param name="expirationMinutes">The number of minutes until the SAS token expires. Defaults to 60 minutes.</param>
    /// <returns>A SAS URI string with read permissions.</returns>
    public static string GenerateSasUri(BlobClient blobClient, int expirationMinutes = DefaultSasTokenExpirationMinutes)
    {
        var sasBuilder = new BlobSasBuilder
        {
            BlobContainerName = blobClient.BlobContainerName,
            BlobName = blobClient.Name,
            Resource = "b", // b = blob
            ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(expirationMinutes)
        };

        sasBuilder.SetPermissions(BlobSasPermissions.Read);

        var sasUri = blobClient.GenerateSasUri(sasBuilder);
        return sasUri.ToString();
    }

    /// <summary>
    /// Uploads a stream to blob storage and returns a SAS URI.
    /// </summary>
    /// <param name="connectionString">The Azure Storage connection string.</param>
    /// <param name="containerName">The name of the blob container.</param>
    /// <param name="blobName">The name of the blob.</param>
    /// <param name="stream">The stream to upload.</param>
    /// <param name="contentType">The content type of the blob.</param>
    /// <param name="expirationMinutes">The number of minutes until the SAS token expires. Defaults to 60 minutes.</param>
    /// <returns>A SAS URI string with read permissions.</returns>
    public static async Task<string> UploadAndGetSasUriAsync(
        string connectionString,
        string containerName,
        string blobName,
        Stream stream,
        string contentType,
        int expirationMinutes = DefaultSasTokenExpirationMinutes)
    {
        var blobServiceClient = new BlobServiceClient(connectionString);
        var containerClient = blobServiceClient.GetBlobContainerClient(containerName);
        await containerClient.CreateIfNotExistsAsync();

        var blobClient = containerClient.GetBlobClient(blobName);

        var options = new BlobUploadOptions
        {
            HttpHeaders = new BlobHttpHeaders
            {
                ContentType = contentType
            }
        };

        await blobClient.UploadAsync(stream, options);

        return GenerateSasUri(blobClient, expirationMinutes);
    }
}
