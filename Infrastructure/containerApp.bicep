@description('The Azure region to deploy resources into')
param location string

@description('Environment Name is used throughout resources to create unique names')
param environmentName string

@description('The name of the resource group to deploy into')
param resourceGroupName string

@description('The name of the container app to deploy')
param appName string

@description('The name of the image to deploy')
param imageName string

@description('Array of secrets to be used in the container app')
param keyVaultSecrets array

@description('Array of environment variables for the container app')
param environment array = []

@description('Minimum number of container app instances')
param minReplicas int = 0

targetScope = 'subscription'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2025-04-01' existing = {
  name: resourceGroupName
}

resource managedEnvironment 'Microsoft.App/managedEnvironments@2025-01-01' existing = {
  name: environmentName
  scope: resourceGroup
}

resource keyVault 'Microsoft.KeyVault/vaults@2025-05-01' existing = {
  name: environmentName
  scope: resourceGroup
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: '${environmentName}-ai'
  scope: resourceGroup
}

resource umi 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'umi-${environmentName}'
  scope: resourceGroup
}

var initialEnvironenment = [
  {
    name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
    value: appInsights.properties.ConnectionString
  }
]

module containerApp 'br/public:avm/res/app/container-app:0.19.0' = {
  name: 'containerAppDeployment'
  scope: resourceGroup
  params: {
    location: resourceGroup.location
    name: appName
    managedIdentities: {
      userAssignedResourceIds: [
        umi.id
      ]
    }
    containers: [
      {
        name: environmentName
        image: '${environmentName}.azurecr.io/${imageName}:latest'
        resources: {
          cpu: '0.25'
          memory: '0.5Gi'
        }
        env: concat(initialEnvironenment, environment)
      }
    ]
    registries: [
      {
        server: '${environmentName}.azurecr.io'
        identity: 'system-environment'
      }
    ]
    secrets: [for item in keyVaultSecrets: {
      name: item.key
      keyVaultUrl: '${keyVault.properties.vaultUri}secrets/${item.value}'
      identity: umi.id
    }]
    scaleSettings: {
      minReplicas: minReplicas
      maxReplicas: 10
      cooldownPeriod: 300
      pollingInterval: 30
    }
    environmentResourceId: managedEnvironment.id
    ingressTargetPort: 4547
    ingressTransport: 'auto'
    ingressExternal: true
    ingressAllowInsecure: false
    corsPolicy: {
      allowedOrigins: [
        '*'
      ]
      allowedHeaders: [
        '*'
      ]
    }
  }
}
