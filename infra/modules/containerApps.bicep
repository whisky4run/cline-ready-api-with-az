// ─────────────────────────────────────────────────────────────
// Azure Container Apps 環境（Container App 本体は app.bicep で作成）
// ─────────────────────────────────────────────────────────────
param location string
param nameSuffix string
param logAnalyticsWorkspaceId string          // customerId（GUID）
param logAnalyticsWorkspaceResourceId string  // ARM リソース ID
param tags object = {}

var caEnvName = 'cae-cline-api-${nameSuffix}'

// Log Analytics Workspace（sharedKey 取得のため existing 参照）
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: last(split(logAnalyticsWorkspaceResourceId, '/'))!
}

// Container Apps 環境
resource caEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: caEnvName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspaceId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

output caEnvironmentId   string = caEnvironment.id
output caEnvironmentName string = caEnvironment.name
