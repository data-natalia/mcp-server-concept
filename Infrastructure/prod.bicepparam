using 'main.bicep'

// Shared registry — keep acrName and acrResourceGroupName identical to dev.bicepparam
param acrName             = 'nras19'
param acrResourceGroupName = 'rg-nras19'

// Prod-environment resources
param containerAppsEnvName = 'nrasprod'
param keyVaultName        = 'nrasprod'
param logAnalyticsName    = 'nrasprod'
param location            = 'westeurope'
param resourceGroupName   = 'rg-nrasprod'
param storageAccountName  = 'stnrasprod'
