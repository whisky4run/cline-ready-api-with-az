// ═══════════════════════════════════════════════════════════════
// cline-ready-api-with-az — フェーズ1: インフラ構築
// 使用方法: deploy.sh から呼び出すこと
// Container App 本体はフェーズ2（app.bicep）でデプロイする
// ═══════════════════════════════════════════════════════════════
targetScope = 'resourceGroup'

@description('デプロイ環境（dev / prod）')
@allowed(['dev', 'prod'])
param env string = 'dev'

@description('デプロイリージョン')
param location string = resourceGroup().location

// リソース名のユニークサフィックス（RG ID から生成・同一 RG なら冪等）
var nameSuffix = take(uniqueString(resourceGroup().id), 8)

// 本スクリプトが作成するすべてのリソースに付与する統一タグ
// destroy.sh はこの project タグで削除対象を識別する
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

module keyVault 'modules/keyVault.bicep' = {
  name: 'keyVault'
  params: {
    location: location
    nameSuffix: nameSuffix
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

module cosmos 'modules/cosmosDb.bicep' = {
  name: 'cosmosDb'
  params: {
    location: location
    nameSuffix: nameSuffix
    env: env
    tags: tags
  }
}

// Container Apps 環境のみ作成（Container App 本体は app.bicep でデプロイ）
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

// UAMI を作成（フェーズ2 の Container App がこの ID を使う）
module managedIdentity 'modules/managedIdentity.bicep' = {
  name: 'managedIdentity'
  params: {
    location: location
    nameSuffix: nameSuffix
    tags: tags
  }
}

// UAMI へのロール割り当て（フェーズ1で完了させ、フェーズ2 開始前に伝播させる）
module roleAssignments 'modules/roleAssignments.bicep' = {
  name: 'roleAssignments'
  params: {
    containerAppPrincipalId: managedIdentity.outputs.uamiPrincipalId
    keyVaultName: keyVault.outputs.keyVaultName
    acrName: acr.outputs.acrName
    cosmosAccountName: cosmos.outputs.cosmosAccountName
  }
}

// ─── デプロイ後の案内用アウトプット ──────────────────────────

@description('Key Vault の URI')
output keyVaultUri string = keyVault.outputs.keyVaultUri

@description('Key Vault 名')
output keyVaultName string = keyVault.outputs.keyVaultName

@description('ACR のログインサーバー')
output acrLoginServer string = acr.outputs.acrLoginServer

@description('ACR 名')
output acrName string = acr.outputs.acrName

@description('Cosmos DB アカウント名')
output cosmosAccountName string = cosmos.outputs.cosmosAccountName

@description('Container Apps 環境 ID（フェーズ2で使用）')
output caEnvironmentId string = containerAppsEnv.outputs.caEnvironmentId

@description('UAMI のリソース ID（フェーズ2で使用）')
output uamiId string = managedIdentity.outputs.uamiId

@description('手動登録が必要な Key Vault シークレット名一覧')
output requiredSecrets array = keyVault.outputs.secretNames
