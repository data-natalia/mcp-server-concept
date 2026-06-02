# Build stage
FROM mcr.microsoft.com/dotnet/sdk:9.0-alpine AS build
WORKDIR /src

# Copy Shared project files for restore
COPY Shared/Shared.csproj Shared/

# Copy project file for restore
COPY CurrER/CurrER.csproj CurrER/

# Restore dependencies (cached layer)
RUN dotnet restore "CurrER/CurrER.csproj"

# Copy remaining source files
COPY Shared/ Shared/
COPY CurrER/ CurrER/

# Build and publish
RUN dotnet publish "CurrER/CurrER.csproj" -c Release -o /app/publish --runtime linux-x64 --self-contained false 

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:9.0-alpine AS final
WORKDIR /app
COPY --from=build /app/publish .
COPY CurrER/appsettings.json ./
EXPOSE 4547
ENTRYPOINT ["dotnet", "CurrER.dll"]