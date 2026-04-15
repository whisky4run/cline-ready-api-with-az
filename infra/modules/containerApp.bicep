// ─────────────────────────────────────────────────────────────
// Azure Container App 本体（環境は既存のものを使用）
// イメージを ACR にプッシュした後に app.bicep から呼び出す
// ─────────────────────────────────────────────────────────────
param location string
param nameSuffix string
param env string
param caEnvironmentId string
param acrLoginServer string
param keyVaultUri string
param appInsightsConnectionString string
param uamiId string
param tags object = {}

var caName = 'ca-cline-api-${nameSuffix}'
var containerImage = '${acrLoginServer}/cline-api:latest'

// Container App 本体（ユーザー割り当てマネージド ID を使用）
// フェーズ1でロール割り当て済みの UAMI を使うことで、
// イメージ pull 時に AcrPull 権限が確実に伝播している
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
      secrets: []
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
            // Key Vault 参照（マネージド ID で取得）
            {
              name: 'AzureAI__Endpoint'
              value: '${keyVaultUri}secrets/AzureAI--Endpoint'
            }
            {
              name: 'KeyVault__Uri'
              value: keyVaultUri
            }
            {
              name: 'ApplicationInsights__ConnectionString'
              value: appInsightsConnectionString
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
