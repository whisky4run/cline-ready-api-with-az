// ═══════════════════════════════════════════════════════════════
// cline-ready-api-with-az (one-api) — インフラ構築
// CosmosDB・Key Vault なし。シークレットは Container App secrets で管理。
// 使用方法: deploy.sh から呼び出すこと（arm/main.json 経由）
// Bicep を変更した場合は build.sh を再実行して arm/ を更新すること
// ═══════════════════════════════════════════════════════════════
targetScope = 'resourceGroup'

@description('デプロイ環境（dev / prod）')
@allowed(['dev', 'prod'])
param env string = 'dev'

@description('デプロイリージョン')
param location string = resourceGroup().location

@description('デプロイする AI モデル名（例: gpt-4.1-mini）')
param modelName string

@description('モデルバージョン（例: 2025-04-14）')
param modelVersion string

// リソース名のユニークサフィックス（RG ID から生成・同一 RG なら冪等）
var nameSuffix = take(uniqueString(resourceGroup().id), 8)

// すべてのリソースに付与する統一タグ（destroy.sh がこの project タグで識別する）
var tags = {
  project: 'cline-ready-api-with-az'
  environment: env
  managedBy: 'bicep'
}

// ─── モジュール呼び出し ───────────────────────────────────────

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    nameSuffix: nameSuffix
    env: env
    tags: tags
  }
}

module acr 'modules/containerRegistry.bicep' = {
  name: 'containerRegistry'
  params: {
    location: location
    nameSuffix: nameSuffix
    env: env
    tags: tags
  }
}

// Container Apps 環境（Container App 本体は app.bicep でデプロイ）
module containerAppsEnv 'modules/containerApps.bicep' = {
  name: 'containerAppsEnv'
  params: {
    location: location
    nameSuffix: nameSuffix
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    logAnalyticsWorkspaceResourceId: monitoring.outputs.logAnalyticsId
    tags: tags
  }
}

// UAMI を作成（app.bicep の Container App がこの ID を使う）
module managedIdentity 'modules/managedIdentity.bicep' = {
  name: 'managedIdentity'
  params: {
    location: location
    nameSuffix: nameSuffix
    tags: tags
  }
}

// UAMI に AcrPull ロールを付与（app.bicep 開始前に伝播させる）
module roleAssignments 'modules/roleAssignments.bicep' = {
  name: 'roleAssignments'
  params: {
    containerAppPrincipalId: managedIdentity.outputs.uamiPrincipalId
    acrName: acr.outputs.acrName
  }
}

// AI Foundry (AIServices) + モデルデプロイ
module aiFoundry 'modules/aiFoundry.bicep' = {
  name: 'aiFoundry'
  params: {
    location: location
    nameSuffix: nameSuffix
    modelName: modelName
    modelVersion: modelVersion
    tags: tags
  }
}

// ─── デプロイ後の案内用アウトプット ──────────────────────────

@description('ACR のログインサーバー')
output acrLoginServer string = acr.outputs.acrLoginServer

@description('ACR 名')
output acrName string = acr.outputs.acrName

@description('Container Apps 環境 ID（app.bicep で使用）')
output caEnvironmentId string = containerAppsEnv.outputs.caEnvironmentId

@description('UAMI のリソース ID（app.bicep で使用）')
output uamiId string = managedIdentity.outputs.uamiId

@description('AI Foundry のエンドポイント URL')
output aiEndpoint string = aiFoundry.outputs.endpoint

@description('AI Foundry のアカウント名（deploy.sh が API キー取得に使用）')
output aiAccountName string = aiFoundry.outputs.accountName

@description('デプロイされたモデル名')
output aiModelName string = aiFoundry.outputs.modelName
