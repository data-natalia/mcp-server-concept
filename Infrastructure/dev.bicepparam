using 'main.bicep'

// Shared registry — keep acrName and acrResourceGroupName identical in prod.bicepparam
param acrName             = 'nras19'
param acrResourceGroupName = 'rg-nras19'

// Dev-environment resources
param containerAppsEnvName = 'nrasdev'
param keyVaultName        = 'nrasdev'
param logAnalyticsName    = 'nrasdev'
param location            = 'swedencentral'
param resourceGroupName   = 'rg-nrasdev'
param storageAccountName  = 'stnrasdev'
