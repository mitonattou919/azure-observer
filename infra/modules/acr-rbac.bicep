// 共有ACR(crmngdev001, rg-mng-dev-001)へのAcrPullロール割り当て (ADR-017)
// このモジュールはmain.bicepからscope: resourceGroup(acrResourceGroupName)で
// 別リソースグループ(rg-mng-dev-001)向けにデプロイされる

@description('組織共通のAzure Container Registry名')
param acrName string

@description('AcrPullロールを付与するManaged IdentityのprincipalId')
param principalId string

var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, principalId, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
