// ─────────────────────────────────────────────────────────────
// Azure Key Vault（シークレットは空で作成・後から手動登録）
// ─────────────────────────────────────────────────────────────
param location string
param nameSuffix string
param tags object = {}

// Key Vault 名は 3〜24 文字・英数字とハイフンのみ
// uniqueString は 13 文字なので先頭 10 文字を使う
var keyVaultName = 'kv-cline-${take(nameSuffix, 10)}'

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    // Container Apps のマネージド ID からのアクセスは roleAssignments で制御する
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// シークレットのプレースホルダーを作成（値は後から手動登録）
// デプロイ直後の案内用に名前だけ定義しておく
var secretNames = [
  'AzureAI--Endpoint'
  'AzureAI--ApiKey'
  'CosmosDb--ConnectionString'
]

output keyVaultId   string = keyVault.id
output keyVaultName string = keyVault.name
output keyVaultUri  string = keyVault.properties.vaultUri
output secretNames  array  = secretNames
