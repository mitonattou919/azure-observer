// リソースグループスコープのRBACロール付与 (Issue #7)
// Key Vault Secrets Userはkey-vault.bicep側でリソーススコープ付与済み(ADR-007)

@description('ロールを付与するManaged IdentityのprincipalId')
param principalId string

var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
// 申請フロー用の最小ロール。VM start/deallocateのみが対象だが組み込みロールに限定版が無いため
// Virtual Machine Contributorを採用(ADR-014)
var virtualMachineContributorRoleId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'

resource readerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, readerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource vmContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, virtualMachineContributorRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', virtualMachineContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
