@description('The Azure region to deploy resources into')
param location string

@description('The name of the Azure Container Registry')
param acrName string

@description('The name of the Log Analytics Workspace')
param logAnalyticsName string

@description('The name of the Container Apps Environment')
param containerAppsEnvName string

@description('The name of the Key Vault')
param keyVaultName string

@description('The name of the resource group to deploy into')
param resourceGroupName string

@description('The name of the Storage Account')
param storageAccountName string

targetScope = 'subscription'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-03-01' = {
  name: resourceGroupName
  location: location
}

module acr 'br/public:avm/res/container-registry/registry:0.9.1' = {
  name: 'acr'
  scope: resourceGroup
  params: {
    name: acrName
    location: location
    acrAdminUserEnabled: true
    acrSku: 'Basic'
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
  }
}

module logAnalytics 'br/public:avm/res/operational-insights/workspace:0.11.2' = {
  name: 'logAnalytics'
  scope: resourceGroup
  params: {
    name: logAnalyticsName
    location: location
    skuName: 'PerGB2018'
  }
}

module appInsights 'br/public:avm/res/insights/component:0.6.0' = {
  name: 'appInsights'
  scope: resourceGroup
  params: {
    name: '${logAnalyticsName}-ai'
    location: location
    applicationType: 'web'
    workspaceResourceId: logAnalytics.outputs.resourceId
  }
}

module containerAppsEnv 'br/public:avm/res/app/managed-environment:0.11.2' = {
  name: 'containerAppsEnv'
  scope: resourceGroup
  params: {
    name: containerAppsEnvName
    location: location
    zoneRedundant: false
    publicNetworkAccess: 'Enabled'
    appInsightsConnectionString: appInsights.outputs.connectionString
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.outputs.logAnalyticsWorkspaceId
        sharedKey: logAnalytics.outputs.primarySharedKey
      }
    }
    managedIdentities: { systemAssigned: true }
  }
}

module keyVault 'br/public:avm/res/key-vault/vault:0.13.3' = {
  name: 'keyVault'
  scope: resourceGroup
  params: {
    name: keyVaultName
    location: location
    enableSoftDelete: true
    enablePurgeProtection: true
    softDeleteRetentionInDays: 7
    enableVaultForDeployment: true
    enableVaultForTemplateDeployment: true
    enableRbacAuthorization: true
    roleAssignments: [
      {
        principalId: containerAppsEnv.outputs.systemAssignedMIPrincipalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Key Vault Secrets User'
      }
      {
        principalId: uma.outputs.principalId
        principalType: 'ServicePrincipal'
        roleDefinitionIdOrName: 'Key Vault Secrets User'
      }
    ]
  }
}

module st 'br/public:avm/res/storage/storage-account:0.27.1' = {
  name: 'storageAccount'
  scope: resourceGroup
  params: {
    name: storageAccountName
    location: location
    skuName: 'Standard_LRS'
    kind: 'StorageV2'
    accessTier: 'Hot'
    allowBlobPublicAccess: true
    enableHierarchicalNamespace: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
    }
    blobServices: {
      corsRules: [
        {
          allowedOrigins: ['*']
          allowedMethods: ['GET']
          maxAgeInSeconds: 10
          exposedHeaders: []
          allowedHeaders: []
        }
      ]
    }
  }
}

module uma 'br/public:avm/res/managed-identity/user-assigned-identity:0.4.2' = {
  name: 'userAssignedManagedIdentity'
  scope: resourceGroup
  params: {
    name: 'umi-${containerAppsEnvName}'
    location: location
  }
}
