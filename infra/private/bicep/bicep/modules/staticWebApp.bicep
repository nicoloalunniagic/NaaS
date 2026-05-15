@description('Name of the Static Web App resource')
param name string

@description('Region for the Static Web App. Note: SWA SKUs are available only in a subset of regions.')
param location string = 'westeurope'

@description('Tags to apply')
param tags object = {}

@description('SKU for the Static Web App')
@allowed([
  'Free'
  'Standard'
])
param sku string = 'Free'

@description('Backend URL the SPA will call (e.g. https://my-api.azurecontainerapps.io)')
param apiBaseUrl string = ''

resource swa 'Microsoft.Web/staticSites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
    tier: sku
  }
  properties: {
    // Build is performed by GitHub Actions (no integrated build).
    repositoryUrl: ''
    branch: ''
    buildProperties: {
      skipGithubActionWorkflowGeneration: true
    }
  }
}

// Expose the configured API base URL as a SWA application setting so the
// front-end (or its build pipeline) can read it if needed.
resource appSettings 'Microsoft.Web/staticSites/config@2023-12-01' = if (!empty(apiBaseUrl)) {
  parent: swa
  name: 'appsettings'
  properties: {
    API_BASE_URL: apiBaseUrl
  }
}

output name string = swa.name
output defaultHostname string = swa.properties.defaultHostname
output url string = 'https://${swa.properties.defaultHostname}'
@secure()
output deploymentToken string = swa.listSecrets().properties.apiKey
