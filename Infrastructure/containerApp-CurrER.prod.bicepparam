using 'containerApp.bicep'

param imageName = 'currer'
param appName = 'currer'
param acrName = 'nras19'
param environmentName = 'nrasprod'
param resourceGroupName = 'rg-nrasprod'
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
    value: 'TODO-public-url-after-first-deploy'
  }
  {
    name: 'CurrERApi__BaseUrl'
    value: 'TODO-upstream-api-base-url'
  }
  {
    name: 'IsTransportStateless'
    value: 'true'
  }
  // Application Insights connection string is automatically added by the template
]
