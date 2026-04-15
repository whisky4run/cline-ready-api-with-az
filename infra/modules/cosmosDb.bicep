// ─────────────────────────────────────────────────────────────
// Azure Cosmos DB（NoSQL）+ データベース + コンテナ定義
// ─────────────────────────────────────────────────────────────
param location string
param nameSuffix string
param env string
param tags object = {}

var cosmosAccountName = 'cosmos-cline-api-${nameSuffix}'
var databaseName      = 'ClineApiDb'

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    // dev はサーバーレス、prod はプロビジョニング済み
    capabilities: env == 'dev' ? [{ name: 'EnableServerless' }] : []
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: env == 'prod'
      }
    ]
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: env == 'prod' ? 'Zone' : 'Local'
      }
    }
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
    // サーバーレスモードでは throughput を設定しない
    options: env == 'prod' ? {
      autoscaleSettings: {
        maxThroughput: 4000
      }
    } : {}
  }
}

// ApiKeys コンテナ（パーティションキー: /memberId）
resource apiKeysContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: 'ApiKeys'
  properties: {
    resource: {
      id: 'ApiKeys'
      partitionKey: {
        paths: ['/memberId']
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [{ path: '/*' }]
        excludedPaths: [{ path: '/"_etag"/?' }]
      }
    }
  }
}

// UsageRecords コンテナ（パーティションキー: /memberId）
resource usageRecordsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: 'UsageRecords'
  properties: {
    resource: {
      id: 'UsageRecords'
      partitionKey: {
        paths: ['/memberId']
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          { path: '/memberId/?' }
          { path: '/requestedAt/?' }
        ]
        excludedPaths: [{ path: '/*' }]
      }
    }
  }
}

// Members コンテナ（パーティションキー: /id）
resource membersContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: 'Members'
  properties: {
    resource: {
      id: 'Members'
      partitionKey: {
        paths: ['/id']
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [{ path: '/*' }]
        excludedPaths: [{ path: '/"_etag"/?' }]
      }
    }
  }
}

output cosmosAccountId   string = cosmosAccount.id
output cosmosAccountName string = cosmosAccount.name
output databaseName      string = databaseName
