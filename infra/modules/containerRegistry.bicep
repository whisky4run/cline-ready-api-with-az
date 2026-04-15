// ─────────────────────────────────────────────────────────────
// Azure Container Registry
// ─────────────────────────────────────────────────────────────
param location string
param nameSuffix string
param env string
param tags object = {}

// ACR 名はグローバルに一意・英数字のみ（ハイフン不可）
var acrName = 'acrclineapi${replace(take(nameSuffix, 10), '-', '')}'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: env == 'prod' ? 'Standard' : 'Basic'
  }
  properties: {
    adminUserEnabled: false  // マネージド ID でプル・管理者アカウントは無効
  }
}

output acrId          string = acr.id
output acrName        string = acr.name
output acrLoginServer string = acr.properties.loginServer
