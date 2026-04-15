using System.ComponentModel;
using ModelContextProtocol.Server;
using {{ServerName}}.Services;

namespace {{ServerName}};

[McpServerToolType]
public class {{ServerName}}Tool
{
    private readonly {{ServerName}}Service _service;

    public {{ServerName}}Tool({{ServerName}}Service service)
    {
        _service = service;
    }

    [McpServerTool, Description("TODO: Replace with your tool description")]
    public async Task<string> ExampleTool(
        [Description("TODO: Replace with your parameter description")] string input)
    {
        return await _service.GetDataAsync(input);
    }
}
