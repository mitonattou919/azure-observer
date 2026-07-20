// Azure MCP Server (Issue #8, ADR-016, ADR-017, ADR-018)
// 公式イメージを自己ホストするContainer App。認証はEasy Auth(authConfig)で保護し、
// アプリ本体には手を入れない(ADR-016)

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

@description('Azure MCP Serverがリッスンするポート。実イメージのドキュメントで確認した実値を渡すこと(デフォルト値は置かない)')
param containerPort int

param tenantId string

@description('MCPサーバー自身を表すリソース側App RegistrationのクライアントID(ADR-016)')
param resourceAppRegistrationClientId string

@description('アクセスを許可するクライアント側App RegistrationのアプリケーションID一覧(Backend + Agent A/B/C。ADR-016)')
param allowedClientAppIds array

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

// Easy Auth(ADR-016): プラットフォーム層でJWT検証を行い、MCPサーバー本体は無改造のまま保護する
resource authConfig 'Microsoft.App/containerApps/authConfigs@2023-05-01' = {
  parent: containerApp
  name: 'current'
  properties: {
    platform: {
      enabled: true
    }
    globalValidation: {
      unauthenticatedClientAction: 'Return401'
    }
    identityProviders: {
      azureActiveDirectory: {
        registration: {
          openIdIssuer: 'https://login.microsoftonline.com/${tenantId}/v2.0'
          clientId: resourceAppRegistrationClientId
        }
        validation: {
          allowedAudiences: [
            'api://${resourceAppRegistrationClientId}'
          ]
          defaultAuthorizationPolicy: {
            allowedApplications: allowedClientAppIds
          }
        }
      }
    }
  }
}

output name string = containerApp.name
output fqdn string = containerApp.properties.configuration.ingress.fqdn
