// ═══════════════════════════════════════════════════════════════
// cline-ready-api-with-az (one-api) — Container App デプロイ
// 使用方法: deploy.sh から、ACR イメージ push 後に呼び出すこと
// 事前条件: main.bicep によるインフラ構築が完了していること
// シークレットは Container App の secrets に直接保存する（Key Vault 不要）
// ═══════════════════════════════════════════════════════════════
targetScope = 'resourceGroup'

@description('デプロイ環境（dev / prod）')
@allowed(['dev', 'prod'])
param env string = 'dev'

@description('デプロイリージョン')
param location string = resourceGroup().location

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

// main.bicep と同じ命名規則（uniqueString は同一 RG で冪等）
var nameSuffix = take(uniqueString(resourceGroup().id), 8)

// main.bicep と同じタグを付与（destroy.sh が project タグで識別する）
var tags = {
  project: 'cline-ready-api-with-az'
  environment: env
  managedBy: 'bicep'
}

// ─── 既存リソースの参照 ───────────────────────────────────────

resource caEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: 'cae-cline-api-${nameSuffix}'
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: 'acrclineapi${nameSuffix}'
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: 'appi-cline-api-${nameSuffix}'
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'id-cline-api-${nameSuffix}'
}

// ─── モジュール呼び出し ───────────────────────────────────────

module containerApp 'modules/containerApp.bicep' = {
  name: 'containerApp'
  params: {
    location: location
    nameSuffix: nameSuffix
    env: env
    caEnvironmentId: caEnvironment.id
    acrLoginServer: acr.properties.loginServer
    azureAiEndpoint: azureAiEndpoint
    azureAiApiKey: azureAiApiKey
    apiKeyValue: apiKeyValue
    modelName: modelName
    appInsightsConnectionString: appInsights.properties.ConnectionString
    uamiId: uami.id
    tags: tags
  }
}

// ─── デプロイ後の案内用アウトプット ──────────────────────────

@description('Container App の FQDN（API のベース URL）')
output apiEndpoint string = 'https://${containerApp.outputs.containerAppFqdn}'

@description('Container App 名')
output containerAppName string = containerApp.outputs.containerAppName
