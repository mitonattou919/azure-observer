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

// 手動でdocker build & pushしたイメージのタグに合わせて更新する(ADR-017)
param mcpServerImage = 'crmngdev001.azurecr.io/azure-mcp-server:REPLACE_ME'
// Azure MCP Serverの実イメージのドキュメントで確認した実際のリッスンポートに置き換えること
param mcpServerContainerPort = 0
// infra/manual-portal-setup.mdの手順でリソース側App Registrationを作成した後、実際のクライアントIDに置き換える(ADR-016)
param mcpServerResourceAppRegistrationClientId = 'REPLACE_ME'
// Backend用 + Agent A/B/C用(Issue #9)のクライアント側App RegistrationのクライアントIDを列挙する(ADR-016)
param mcpServerAllowedClientAppIds = [
  'REPLACE_ME_BACKEND_CLIENT_APP_ID'
  'REPLACE_ME_AGENT_A_CLIENT_APP_ID'
  'REPLACE_ME_AGENT_B_CLIENT_APP_ID'
  'REPLACE_ME_AGENT_C_CLIENT_APP_ID'
]
