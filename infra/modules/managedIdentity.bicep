// ─────────────────────────────────────────────────────────────
// ユーザー割り当てマネージド ID（UAMI）
// フェーズ1で作成し、ロール割り当てと共に伝播を完了させる。
// フェーズ2の Container App がこの ID を使って ACR からイメージを pull する。
// ─────────────────────────────────────────────────────────────
param location string
param nameSuffix string
param tags object = {}

var uamiName = 'id-cline-api-${nameSuffix}'

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
  tags: tags
}

output uamiId          string = uami.id
output uamiName        string = uami.name
output uamiPrincipalId string = uami.properties.principalId
output uamiClientId    string = uami.properties.clientId
