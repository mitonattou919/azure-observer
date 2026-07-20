// Azure MCP Server (Issue #8, Issue #28, ADR-017, ADR-018, ADR-019)
// 公式イメージを自己ホストするContainer App。認証はアプリ内蔵のEntra ID認証で保護し、
// プラットフォーム層(Easy Auth)は使わない(ADR-019)

param name string
param location string
param tags object
param containerAppsEnvironmentId string

param managedIdentityId string
param managedIdentityClientId string

@description('共有ACR(crmngdev001)のログインサーバー(例: crmngdev001.azurecr.io)')
param acrLoginServer string

@description('コンテナイメージのフルリファレンス(例: crmngdev001.azurecr.io/azure-mcp-server:latest)')
param image string

@description('有効化するAzure MCPのツール種別(--namespace)の配列。--namespaceは複数指定可能なオプションのため配列で受け取る。Issue #4で申請フロー対象操作が確定してから確定値に置き換える(ADR-019)')
param namespaces array

param tenantId string

@description('MCPサーバー自身を表すリソース側App RegistrationのクライアントID。アプリ内蔵認証のAzureAd__ClientIdに使う(ADR-019)')
param resourceAppRegistrationClientId string

// アプリ内蔵認証はASPNETCORE_URLSで待ち受けポートを指定する自己申告値であり、実イメージ固有の
// 固定値ではない。Microsoft公式サンプル(azmcp-foundry-aca-mi)に合わせて8080固定を採用する(ADR-019)
var containerPort = 8080

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentityId}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      activeRevisionsMode: 'Single'
      registries: [
        {
          server: acrLoginServer
          identity: managedIdentityId
        }
      ]
      ingress: {
        external: true
        targetPort: containerPort
        transport: 'auto'
      }
    }
    template: {
      containers: [
        {
          name: 'azure-mcp-server'
          image: image
          // --transport httpで起動しないとデフォルトのstdioトランスポートのままIngress経由で疎通しない(ADR-019)
          // --namespaceは複数指定可能なオプションのため、namespacesの各要素ごとに--namespace <ns>を展開する
          args: concat([
            '--transport'
            'http'
            '--outgoing-auth-strategy'
            'UseHostingEnvironmentIdentity'
            '--mode'
            'all'
          ], flatten([for ns in namespaces: [
            '--namespace'
            ns
          ]]))
          env: [
            {
              name: 'AZURE_MCP_INCLUDE_PRODUCTION_CREDENTIALS'
              value: 'true'
            }
            {
              // 複数UAMIが将来アタッチされるケースに備え、使用するIdentityを明示する
              name: 'AZURE_CLIENT_ID'
              value: managedIdentityClientId
            }
            {
              name: 'AZURE_TOKEN_CREDENTIALS'
              value: 'ManagedIdentityCredential'
            }
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: 'Production'
            }
            {
              name: 'ASPNETCORE_URLS'
              value: 'http://+:${containerPort}'
            }
            {
              // アプリ内蔵のEntra ID受信認証の設定(ADR-019)。値はresourceAppRegistrationClientId(手順8-1で
              // 手動作成済みのapp-sre-dev-001-mcp-server)のテナントID/クライアントIDと一致させること
              name: 'AzureAd__Instance'
              value: 'https://login.microsoftonline.com/'
            }
            {
              name: 'AzureAd__TenantId'
              value: tenantId
            }
            {
              name: 'AzureAd__ClientId'
              value: resourceAppRegistrationClientId
            }
            {
              // Container Apps IngressでHTTPSは終端済みのため、コンテナ内部はHTTPで待ち受ける(ADR-019)
              name: 'AZURE_MCP_DANGEROUSLY_DISABLE_HTTPS_REDIRECTION'
              value: 'true'
            }
            {
              // Ingress経由のリクエストでプロトコルスキームをHTTPSとして正しく認識させる(ADR-019)
              name: 'AZURE_MCP_DANGEROUSLY_ENABLE_FORWARDED_HEADERS'
              value: 'true'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
        }
      ]
      // ゼロスケール(ADR-018)。呼び出し頻度が変数的なため、コスト優先でコールドスタートを許容する
      scale: {
        minReplicas: 0
        maxReplicas: 3
      }
    }
  }
}

output name string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
