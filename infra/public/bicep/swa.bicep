@description('Azure region for the Static Web App')
param location string = resourceGroup().location

@description('Prefix used for Azure resource names. Use only lowercase letters and digits.')
@minLength(3)
@maxLength(12)
param namePrefix string

@description('SKU for the Static Web App')
@allowed([
  'Free'
  'Standard'
])
param staticWebAppSku string = 'Free'

@description('Backend URL the SPA will call')
param apiBaseUrl string = ''

var tags = {
  app: 'no-as-a-service'
  managedBy: 'bicep'
}

module staticWebApp './modules/staticWebApp.bicep' = {
  name: 'staticWebApp'
  params: {
    name: '${namePrefix}-web'
    location: location
    tags: tags
    sku: staticWebAppSku
    apiBaseUrl: apiBaseUrl
  }
}

output staticWebAppName string = staticWebApp.outputs.name
output staticWebAppUrl string = staticWebApp.outputs.url
@secure()
output staticWebAppDeploymentToken string = staticWebApp.outputs.deploymentToken
