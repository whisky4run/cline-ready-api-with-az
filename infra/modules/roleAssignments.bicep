// ─────────────────────────────────────────────────────────────
// マネージド ID へのロール割り当て
// ─────────────────────────────────────────────────────────────
param containerAppPrincipalId string
param keyVaultName            string
param acrName                 string
param cosmosAccountName       string

// ─── ビルトインロール ID ───────────────────────────────────────
// Key Vault Secrets User
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'
// AcrPull
var acrPullRoleId = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
// Cosmos DB Built-in Data Contributor（SQL API 組み込みロール）
var cosmosDbDataContributorRoleDefinitionId = '00000000-0000-0000-0000-000000000002'

// 既存リソースを参照
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' existing = {
  name: cosmosAccountName
}

// Key Vault Secrets User → Container App マネージド ID
resource kvSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, containerAppPrincipalId, keyVaultSecretsUserRoleId)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: containerAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// AcrPull → Container App マネージド ID
resource acrPullAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, containerAppPrincipalId, acrPullRoleId)
  scope: acr
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleId)
    principalId: containerAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Cosmos DB Built-in Data Contributor → Container App マネージド ID
// Cosmos DB の SQL ロール割り当ては ARM ロールとは別の仕組みを使う
resource cosmosRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, containerAppPrincipalId, cosmosDbDataContributorRoleDefinitionId)
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDbDataContributorRoleDefinitionId}'
    principalId: containerAppPrincipalId
    scope: cosmosAccount.id
  }
}
