using 'main.bicep'

// Shared registry — keep acrName and acrResourceGroupName identical in prod.bicepparam
param acrName             = 'mymcpacr'
param acrResourceGroupName = 'rg-mymcpacr'

// Dev-environment resources
param containerAppsEnvName = 'mymcpdev'
param keyVaultName        = 'mymcpdev'
param logAnalyticsName    = 'mymcpdev'
param location            = 'westeurope'
param resourceGroupName   = 'rg-mymcpdev'
param storageAccountName  = 'stmymcpdev'
