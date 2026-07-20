// activity_log用Table Storage (ADR-005)
// Table Storageのテーブル名はアンダースコア不可(英数字のみ)のため `activitylog` とする

param name string
param location string
param tags object

@description('Storage Table Data Contributorロールを付与するManaged IdentityのprincipalId')
param principalId string

var storageTableDataContributorRoleId = '0a9a7e81-cd61-4011-81ae-220898e0eb9d'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    // Managed Identity経由のシークレットレス認証(ADR-007の思想)に統一し、共有キー認証は無効化する
    allowSharedKeyAccess: false
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource activityLogTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
  parent: tableService
  name: 'activitylog'
}

resource tableDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, principalId, storageTableDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageTableDataContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output name string = storageAccount.name
output id string = storageAccount.id
