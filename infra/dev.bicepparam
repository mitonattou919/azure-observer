using 'main.bicep'

param workload = 'sre'
param env = 'dev'
param instance = '001'
param ownerEmail = 'REPLACE_ME@example.com'
// stsredev001はグローバル一意制約で既に使用済みだったためsaプレフィックスにフォールバック
param storageAccountNameOverride = 'sasredev001'
// kv-sre-dev-001もグローバル一意制約で既に使用済みだったためinstanceを003にフォールバック
param keyVaultNameOverride = 'kv-sre-dev-003'

// 組織共通ACR (ADR-017)
param acrName = 'crmngdev001'
param acrResourceGroupName = 'rg-mng-dev-001'

// az acr importで共有ACRへ取り込んだ公式イメージのタグに合わせて更新する(ADR-017, ADR-019)
param mcpServerImage = 'crmngdev001.azurecr.io/azure-mcp-server:REPLACE_ME'
// Issue #4で申請フロー対象操作が確定してから、有効化するAzure MCPのツール種別に置き換える(ADR-019)
param mcpServerNamespaces = [
  'REPLACE_ME_NAMESPACE_ISSUE4'
]
// infra/manual-portal-setup.mdの手順でリソース側App Registrationを作成した後、実際のクライアントIDに置き換える(ADR-019)
param mcpServerResourceAppRegistrationClientId = 'REPLACE_ME'
