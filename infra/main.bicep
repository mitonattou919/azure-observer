targetScope = 'resourceGroup'

import { environment, workloadCode, instanceNumber, resourceTags } from 'types.bicep'

@description('CAFリソース略語を除くサービス識別子(3文字固定)')
param workload workloadCode = 'sre'

param env environment

@description('ゼロパディング3桁の連番')
param instance instanceNumber = '001'

@description('デプロイ先リージョン')
param location string = resourceGroup().location

@description('所有者のメールアドレス(プレースホルダー)')
param ownerEmail string

@description('Storage Account名の上書き。命名規則のデフォルト値がグローバル一意制約で衝突した場合に指定する')
param storageAccountNameOverride string = ''

@description('Key Vault名の上書き。命名規則のデフォルト値がグローバル一意制約で衝突した場合に指定する')
param keyVaultNameOverride string = ''

var namePrefix = '${workload}-${env}-${instance}'
var defaultStorageAccountName = toLower('st${workload}${env}${instance}')
var storageAccountName = empty(storageAccountNameOverride) ? defaultStorageAccountName : storageAccountNameOverride
var defaultKeyVaultName = 'kv-${namePrefix}'
var keyVaultName = empty(keyVaultNameOverride) ? defaultKeyVaultName : keyVaultNameOverride

var tags resourceTags = {
  Owner: ownerEmail
  Project: '${workload}: Azure Observer for SRE'
  Environment: env
}

module managedIdentity 'modules/managed-identity.bicep' = {
  name: 'managed-identity'
  params: {
    name: 'id-${namePrefix}'
    location: location
    tags: tags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    // Storage Accountはハイフン不可のためnamePrefixを使わず個別連結する
    name: storageAccountName
    location: location
    tags: tags
    principalId: managedIdentity.outputs.principalId
  }
}

module keyVault 'modules/key-vault.bicep' = {
  name: 'key-vault'
  params: {
    name: keyVaultName
    location: location
    tags: tags
    tenantId: tenant().tenantId
    principalId: managedIdentity.outputs.principalId
  }
}

module rbac 'modules/rbac.bicep' = {
  name: 'rbac'
  params: {
    principalId: managedIdentity.outputs.principalId
  }
}

output managedIdentityId string = managedIdentity.outputs.id
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId
output managedIdentityClientId string = managedIdentity.outputs.clientId
output storageAccountName string = storage.outputs.name
output keyVaultName string = keyVault.outputs.name
