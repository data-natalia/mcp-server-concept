using '../../../Infrastructure/containerApp.bicep'

param location = 'westeurope'
param imageName = '{{servername}}'
param appName = '{{servername}}'
param environmentName = 'TODO-container-apps-environment-name'
param resourceGroupName = 'TODO-resource-group-name'
param keyVaultSecrets = [
  {
    key: '{{servername}}clientid' // Must be lowercase - used in secretRef
    value: '{{ServerName}}ClientId' // PascalCase - actual Key Vault secret name
  }
  {
    key: '{{servername}}clientsecret' // Must be lowercase - used in secretRef
    value: '{{ServerName}}ClientSecret' // PascalCase - actual Key Vault secret name
  }
  {
    key: '{{servername}}tenantid' // Must be lowercase - used in secretRef
    value: '{{ServerName}}TenantId' // PascalCase - actual Key Vault secret name
  }
]
param environment = [
  {
    name: 'EntraIdAuth__TenantId'
    secretRef: '{{servername}}tenantid'
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
    name: '{{ApiConfigSection}}__BaseUrl'
    value: 'TODO-upstream-api-base-url'
  }
  {
    name: 'IsTransportStateless'
    value: 'true'
  }
  // Application Insights connection string is automatically added by the template
]
