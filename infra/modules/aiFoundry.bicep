// ─────────────────────────────────────────────────────────────
// Azure AI Foundry (Cognitive Services / AIServices) + モデルデプロイ
// deploy.sh のフェーズ1から呼び出す（main.bicep 経由）
// ─────────────────────────────────────────────────────────────
param location string
param nameSuffix string

@description('デプロイするモデル名（例: gpt-4.1-mini）')
param modelName string

@description('モデルバージョン（例: 2025-04-14）')
param modelVersion string

@description('モデルの TPM キャパシティ（千トークン/分）')
param modelCapacity int = 10

param tags object = {}

// customSubDomainName はグローバル一意必須。nameSuffix（RG IDから8文字）で衝突を回避
var accountName = 'ai-cline-api-${nameSuffix}'

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: accountName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: accountName
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false  // API キー認証を有効化
  }
}

// モデルデプロイ名 = modelName（appsettings.json のキー・Cline のモデル指定と一致させる）
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: aiFoundry
  name: modelName
  sku: {
    name: 'GlobalStandard'    // 広いリージョンで利用可能
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

output endpoint    string = aiFoundry.properties.endpoint
output accountName string = aiFoundry.name
output modelName   string = modelDeployment.name
