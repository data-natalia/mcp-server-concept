using System.ComponentModel;
using ModelContextProtocol.Server;
using CurrER.Services;

namespace CurrER;

[McpServerToolType]
public class CurrERTool
{
    private readonly CurrERService _service;

    public CurrERTool(CurrERService service)
    {
        _service = service;
    }

    [McpServerTool, Description("List resources from the public D&D 5e API by category, such as monsters, spells, classes, or equipment.")]
    public async Task<string> ListDndResources(
        [Description("API category to list, for example monsters, spells, classes, or equipment")] string category)
    {
        return await _service.ListDndResourcesAsync(category);
    }

    [McpServerTool, Description("Retrieve a D&D 5e API resource by category and resource name slug.")]
    public async Task<string> GetDndResource(
        [Description("API category, for example monsters, spells, classes, or equipment")] string category,
        [Description("Resource name slug, for example ancient-black-dragon, acid-arrow, or barbarian")] string resourceName)
    {
        return await _service.GetDndResourceAsync(category, resourceName);
    }
}
