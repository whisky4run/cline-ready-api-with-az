// ═══════════════════════════════════════════════════════════════
// cline-ready-api-with-az — フェーズ2: Container App デプロイ
// 使用方法: deploy.sh から、ACR イメージ push 後に呼び出すこと
// 事前条件: main.bicep によるインフラ構築が完了していること
// ═══════════════════════════════════════════════════════════════
targetScope = 'resourceGroup'

@description('デプロイ環境（dev / prod）')
@allowed(['dev', 'prod'])
param env string = 'dev'

@description('デプロイリージョン')
param location string = resourceGroup().location

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

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: 'kv-cline-${nameSuffix}'
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: 'appi-cline-api-${nameSuffix}'
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: 'cosmos-cline-api-${nameSuffix}'
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
    keyVaultUri: keyVault.properties.vaultUri
    appInsightsConnectionString: appInsights.properties.ConnectionString
    tags: tags
  }
}

// ロール割り当ては Container App の ID が確定してから実行
module roleAssignments 'modules/roleAssignments.bicep' = {
  name: 'roleAssignments'
  params: {
    containerAppPrincipalId: containerApp.outputs.containerAppPrincipalId
    keyVaultName: keyVault.name
    acrName: acr.name
    cosmosAccountName: cosmosAccount.name
  }
}

// ─── デプロイ後の案内用アウトプット ──────────────────────────

@description('Container App の FQDN（API のベース URL）')
output apiEndpoint string = 'https://${containerApp.outputs.containerAppFqdn}'

@description('Container App 名')
output containerAppName string = containerApp.outputs.containerAppName

@description('Container App のマネージド ID プリンシパル ID')
output containerAppPrincipalId string = containerApp.outputs.containerAppPrincipalId
