FROM mcr.microsoft.com/dotnet/sdk:9.0-alpine AS build
WORKDIR /src

COPY ["MCPServers/Shared/Shared.csproj", "MCPServers/Shared/"]
COPY ["MCPServers/{{ServerName}}/{{ServerName}}.csproj", "MCPServers/{{ServerName}}/"]
RUN dotnet restore "MCPServers/{{ServerName}}/{{ServerName}}.csproj"

COPY MCPServers/Shared/ MCPServers/Shared/
COPY MCPServers/{{ServerName}}/ MCPServers/{{ServerName}}/

RUN dotnet publish "MCPServers/{{ServerName}}/{{ServerName}}.csproj" \
    -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:9.0-alpine AS runtime
WORKDIR /app
EXPOSE {{Port}}
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "{{ServerName}}.dll"]
