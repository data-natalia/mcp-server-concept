using 'containerApp.bicep'

param imageName = 'currer'
param appName = 'currer'
param acrName = 'nras19'
param environmentName = 'nrasdev'
param resourceGroupName = 'rg-nrasdev'
param keyVaultSecrets = [
  {
    key: 'currerclientid' // Must be lowercase - used in secretRef
    value: 'CurrERClientId' // PascalCase - actual Key Vault secret name
  }
  {
    key: 'currerclientsecret' // Must be lowercase - used in secretRef
    value: 'CurrERClientSecret' // PascalCase - actual Key Vault secret name
  }
  {
    key: 'currertenantid' // Must be lowercase - used in secretRef
    value: 'CurrERTenantId' // PascalCase - actual Key Vault secret name
  }
]
param environment = [
  {
    name: 'EntraIdAuth__TenantId'
    secretRef: 'currertenantid'
  }
  {
    name: 'EntraIdAuth__ClientId'
    secretRef: 'currerclientid'
  }
  {
    name: 'EntraIdAuth__ClientSecret'
    secretRef: 'currerclientsecret'
  }
  {
    name: 'EntraIdAuth__PublicUrl'
    value: 'https://CurrER.kinddune-9717cfc3.swedencentral.azurecontainerapps.io'
  }
  {
    name: 'CurrERApi__BaseUrl'
    value: 'https://www.dnd5eapi.co/api'
  }
  {
    name: 'IsTransportStateless'
    value: 'true'
  }
  // Application Insights connection string is automatically added by the template
]
