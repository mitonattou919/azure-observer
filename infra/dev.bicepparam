using 'main.bicep'

param workload = 'sre'
param env = 'dev'
param instance = '001'
param ownerEmail = 'REPLACE_ME@example.com'
// stsredev001はグローバル一意制約で既に使用済みだったためsaプレフィックスにフォールバック
param storageAccountNameOverride = 'sasredev001'
// kv-sre-dev-001もグローバル一意制約で既に使用済みだったためinstanceを003にフォールバック
param keyVaultNameOverride = 'kv-sre-dev-003'
