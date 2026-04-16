// ─────────────────────────────────────────────────────────────
// Azure Container App 本体（環境は既存のものを使用）
// シークレットは Container App の secrets に直接保存（Key Vault 不要）
// イメージを ACR にプッシュした後に app.bicep から呼び出す
// ─────────────────────────────────────────────────────────────
param location string
param nameSuffix string
param env string
param caEnvironmentId string
param acrLoginServer string

@description('Azure AI Foundry エンドポイント URL')
param azureAiEndpoint string

@description('Azure AI Foundry API キー')
@secure()
param azureAiApiKey string

@description('クライアント認証用 API キー（Cline から渡す値）')
@secure()
param apiKeyValue string

@description('デプロイされた AI モデル名（例: gpt-4.1-mini）')
param modelName string

param appInsightsConnectionString string
param uamiId string
param tags object = {}

var caName = 'ca-cline-api-${nameSuffix}'
var containerImage = '${acrLoginServer}/cline-api:latest'

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: caName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uamiId}': {}
    }
  }
  properties: {
    environmentId: caEnvironmentId
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false
      }
      registries: [
        {
          server: acrLoginServer
          identity: uamiId
        }
      ]
      // シークレットは Container App に直接保存（Key Vault 参照不要）
      secrets: [
        {
          name: 'azure-ai-api-key'
          value: azureAiApiKey
        }
        {
          name: 'api-key-value'
          value: apiKeyValue
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'cline-api'
          image: containerImage
          resources: {
            cpu: env == 'prod' ? json('1.0') : json('0.5')
            memory: env == 'prod' ? '2Gi' : '1Gi'
          }
          env: [
            {
              name: 'AzureAI__Endpoint'
              value: azureAiEndpoint
            }
            {
              name: 'AzureAI__ApiKey'
              secretRef: 'azure-ai-api-key'
            }
            {
              name: 'ApiKey__Value'
              secretRef: 'api-key-value'
            }
            {
              name: 'ApplicationInsights__ConnectionString'
              value: appInsightsConnectionString
            }
            {
              name: 'AzureAI__ModelName'
              value: modelName
            }
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: env == 'prod' ? 'Production' : 'Development'
            }
          ]
        }
      ]
      scale: {
        minReplicas: env == 'prod' ? 1 : 0
        maxReplicas: env == 'prod' ? 10 : 3
        rules: [
          {
            name: 'http-scaling'
            http: {
              metadata: {
                concurrentRequests: '100'
              }
            }
          }
        ]
      }
    }
  }
}

output containerAppId   string = containerApp.id
output containerAppName string = containerApp.name
output containerAppFqdn string = containerApp.properties.configuration.ingress.fqdn
