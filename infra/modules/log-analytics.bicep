// Container Apps Environment用Log Analyticsワークスペース (ADR-015, ADR-018)
// ACA標準ログ(stdout)の収集先。Application Insights等の専用APM基盤は導入しない(ADR-015)

param name string
param location string
param tags object

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

output id string = logAnalyticsWorkspace.id
output name string = logAnalyticsWorkspace.name
output customerId string = logAnalyticsWorkspace.properties.customerId
