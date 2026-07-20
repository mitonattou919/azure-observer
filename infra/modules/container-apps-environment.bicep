// Container Apps Environment (ADR-018)
// 組織共通のEnvironmentは存在しないため新規作成する。将来Backend用Container App(Issue #11)も
// このEnvironmentを共有する想定(Environment自体の分割コストに見合うメリットがないため)

param name string
param location string
param tags object
param logAnalyticsCustomerId string

@secure()
param logAnalyticsSharedKey string

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsCustomerId
        sharedKey: logAnalyticsSharedKey
      }
    }
  }
}

output id string = containerAppsEnvironment.id
output name string = containerAppsEnvironment.name
