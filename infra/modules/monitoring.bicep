// ─────────────────────────────────────────────────────────────
// Log Analytics Workspace + Application Insights
// ─────────────────────────────────────────────────────────────
param location string
param nameSuffix string
param env string
param tags object = {}

var logAnalyticsName = 'law-cline-api-${nameSuffix}'
var appInsightsName  = 'appi-cline-api-${nameSuffix}'

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: env == 'prod' ? 90 : 30
  }
}

// Application Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    SamplingPercentage: env == 'prod' ? 10 : 100
  }
}

output logAnalyticsId              string = logAnalytics.id
output logAnalyticsWorkspaceId     string = logAnalytics.properties.customerId
output appInsightsId               string = appInsights.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
