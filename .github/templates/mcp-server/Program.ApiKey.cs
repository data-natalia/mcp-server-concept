using {{ServerName}};
using {{ServerName}}.Services;
using MCPServers.Shared.Extensions;

var builder = WebApplication.CreateBuilder(args);

if (builder.Environment.IsDevelopment())
{
    builder.Logging.AddConsole();
    builder.Logging.AddDebug();
}

var configuration = ConfigurationExtensions.BuildMcpConfiguration(includeEnvironmentVariables: true);
builder.Services.AddSingleton<IConfiguration>(configuration);

builder.Services.AddHttpClient();
builder.Services.AddScoped(sp => sp.GetRequiredService<IHttpClientFactory>().CreateClient());

builder.Services.AddScoped<{{ServerName}}Service>();

builder.Services.AddMcpOpenTelemetry(builder.Logging);

builder.Services.AddMcpAuthentication(configuration, validateIssuer: true);

builder.Services.AddAuthorization();

var isTransportStateless = bool.Parse(configuration["IsTransportStateless"] ?? "true");
builder.Services.AddMcpServer()
    .WithHttpTransport(options => options.Stateless = isTransportStateless)
    .WithTools<{{ServerName}}Tool>();

var app = builder.Build();

app.UseAuthentication();
app.UseAuthorization();

var serverUrl = configuration["ServerUrl"] ?? "http://0.0.0.0:{{Port}}";

app.MapMcp().RequireAuthorization();

app.Run(serverUrl);
