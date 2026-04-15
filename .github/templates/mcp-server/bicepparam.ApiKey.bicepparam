using '../../../Infrastructure/containerApp.bicep'

param location = 'westeurope'
param imageName = '{{servername}}'
param appName = '{{servername}}'
param environmentName = 'TODO-container-apps-environment-name'
param resourceGroupName = 'TODO-resource-group-name'
param keyVaultSecrets = [
  {
    key: '{{servername}}apikey' // Must be lowercase - used in secretRef
    value: '{{ServerName}}ApiKey' // PascalCase - actual Key Vault secret name
  }
  {
    key: '{{servername}}clientid' // Must be lowercase - used in secretRef
    value: '{{ServerName}}ClientId' // PascalCase - actual Key Vault secret name
  }
  {
    key: '{{servername}}clientsecret' // Must be lowercase - used in secretRef
    value: '{{ServerName}}ClientSecret' // PascalCase - actual Key Vault secret name
  }
]
param environment = [
  {
    name: '{{ApiConfigSection}}__ApiKey'
    secretRef: '{{servername}}apikey'
  }
  {
    name: '{{ApiConfigSection}}__BaseUrl'
    value: 'TODO-upstream-api-base-url'
  }
  {
    name: 'EntraIdAuth__TenantId'
    value: 'TODO-tenant-id'
  }
  {
    name: 'EntraIdAuth__ClientId'
    secretRef: '{{servername}}clientid'
  }
  {
    name: 'EntraIdAuth__ClientSecret'
    secretRef: '{{servername}}clientsecret'
  }
  {
    name: 'EntraIdAuth__PublicUrl'
    value: 'TODO-public-url-after-first-deploy'
  }
  {
    name: 'IsTransportStateless'
    value: 'true'
  }
  // Application Insights connection string is automatically added by the template
]
