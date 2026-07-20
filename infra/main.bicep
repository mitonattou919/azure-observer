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

@description('組織共通のAzure Container Registry名 (ADR-017)')
param acrName string

@description('組織共通ACRのリソースグループ名 (ADR-017)')
param acrResourceGroupName string

@description('Azure MCP Serverのコンテナイメージのフルリファレンス (ADR-017)')
param mcpServerImage string

@description('Azure MCP Serverがリッスンするポート。実イメージのドキュメントで確認した実値を渡すこと')
param mcpServerContainerPort int

@description('MCPサーバー自身を表すリソース側App RegistrationのクライアントID (ADR-016, Issue #8で作成)')
param mcpServerResourceAppRegistrationClientId string

@description('MCPサーバーへのアクセスを許可するクライアント側App RegistrationのアプリケーションID一覧。Backend用(Issue #8)に加え、Issue #9でAgent A/B/C用が追加され次第ここに追記する (ADR-016)')
param mcpServerAllowedClientAppIds array

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

// 共有ACR(別RG)側へのAcrPull付与。scopeでrg-mng-dev-001向けにデプロイする (ADR-017)
module acrRbac 'modules/acr-rbac.bicep' = {
  name: 'acr-rbac'
  scope: resourceGroup(acrResourceGroupName)
  params: {
    acrName: acrName
    principalId: managedIdentity.outputs.principalId
  }
}

module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'log-analytics'
  params: {
    name: 'log-${namePrefix}'
    location: location
    tags: tags
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalytics.outputs.name
}

module containerAppsEnvironment 'modules/container-apps-environment.bicep' = {
  name: 'container-apps-environment'
  params: {
    name: 'cae-${namePrefix}'
    location: location
    tags: tags
    logAnalyticsCustomerId: logAnalytics.outputs.customerId
    logAnalyticsSharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
  }
}

module mcpServer 'modules/mcp-server.bicep' = {
  name: 'mcp-server'
  params: {
    name: 'ca-${namePrefix}-mcp'
    location: location
    tags: tags
    containerAppsEnvironmentId: containerAppsEnvironment.outputs.id
    managedIdentityId: managedIdentity.outputs.id
    managedIdentityClientId: managedIdentity.outputs.clientId
    acrLoginServer: '${acrName}.azurecr.io'
    image: mcpServerImage
    containerPort: mcpServerContainerPort
    tenantId: tenant().tenantId
    resourceAppRegistrationClientId: mcpServerResourceAppRegistrationClientId
    allowedClientAppIds: mcpServerAllowedClientAppIds
  }
  dependsOn: [
    acrRbac
  ]
}

output managedIdentityId string = managedIdentity.outputs.id
output managedIdentityPrincipalId string = managedIdentity.outputs.principalId
output managedIdentityClientId string = managedIdentity.outputs.clientId
output storageAccountName string = storage.outputs.name
output keyVaultName string = keyVault.outputs.name
output mcpServerFqdn string = mcpServer.outputs.fqdn
