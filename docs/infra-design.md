# インフラ設計

## 概要

Azure 上で動作するプロキシ API システムのインフラ構成。
IaC は Bicep で管理し、dev / prod の2環境を用意する。

---

## Azure リソース構成

```
リソースグループ: rg-cline-api-{env}
│
├── Azure Container Apps（API ホスティング）
│     ca-cline-api-{env}
│
├── Azure Container Apps 環境
│     cae-cline-api-{env}
│
├── Azure Cosmos DB（データストア）
│     cosmos-cline-api-{env}
│     └── Database: ClineApiDb
│           ├── Container: ApiKeys
│           ├── Container: UsageRecords
│           └── Container: Members
│
├── Azure Key Vault（シークレット管理）
│     kv-cline-api-{env}
│
├── Azure Container Registry（コンテナイメージ）
│     acr-clineapi-{env}
│
├── Azure Application Insights（監視）
│     appi-cline-api-{env}
│
└── Azure Log Analytics Workspace
      law-cline-api-{env}
```

---

## 各リソースの詳細

### Azure Container Apps

| 項目 | dev | prod |
|---|---|---|
| CPU | 0.5 vCPU | 1.0 vCPU |
| メモリ | 1.0 Gi | 2.0 Gi |
| 最小レプリカ数 | 0（スケールダウンあり） | 1 |
| 最大レプリカ数 | 3 | 10 |
| スケールルール | HTTP リクエスト数（閾値: 100 req/s） | 同左 |
| イングレス | 外部公開（HTTPS） | 外部公開（HTTPS） |

- マネージド ID を使用して Key Vault・Cosmos DB にアクセス（接続文字列を環境変数に直接持たない）
- コンテナイメージは Azure Container Registry からプル

### Azure Cosmos DB

| 項目 | 設定値 |
|---|---|
| API 種別 | NoSQL（Core API） |
| 容量モード | サーバーレス（dev）/ プロビジョニング済み（prod） |
| 冗長性 | ローカル冗長（dev）/ ゾーン冗長（prod） |
| バックアップ | 定期バックアップ（デフォルト） |

#### コンテナ定義

**ApiKeys**
- パーティションキー: `/memberId`
- 用途: メンバーの API キー（ハッシュ）を管理

**UsageRecords**
- パーティションキー: `/memberId`
- 用途: リクエストごとのトークン使用量を記録
- TTL: 設定しない（永続保存）

**Members**
- パーティションキー: `/id`
- 用途: メンバー情報（名前、権限、有効フラグ）を管理

### Azure Key Vault

以下のシークレットを管理する：

| シークレット名 | 内容 |
|---|---|
| `AzureAI--Endpoint` | Azure AI Foundry の推論エンドポイント URL |
| `AzureAI--ApiKey` | Azure AI Foundry の API キー |
| `CosmosDb--ConnectionString` | Cosmos DB の接続文字列 |

- Container Apps のマネージド ID に Key Vault Secrets User ロールを付与
- アプリ起動時に Azure SDK 経由でシークレットを取得

### Azure Container Registry

- sku: Basic（dev）/ Standard（prod）
- 管理者アカウント: 無効（マネージド ID でプル）
- Container Apps の マネージド ID に AcrPull ロールを付与

### Azure Application Insights

- サンプリング率: 100%（dev）/ 10%（prod）
- Log Analytics Workspace と連携
- 以下をカスタム追跡:
  - リクエストごとのメンバーID（カスタムプロパティ）
  - Azure AI Foundry へのレイテンシ（依存関係トラッキング）
  - トークン使用量（カスタムメトリクス）

---

## ネットワーク設計

- Container Apps のイングレスは HTTPS のみ許可（HTTP → HTTPS リダイレクトなし、HTTP は拒否）
- dev 環境は IP 制限なし（開発チームメンバーが自由にアクセス）
- prod 環境も IP 制限なし（API キー認証で保護）
- Cosmos DB・Key Vault はサービスエンドポイントまたは Private Endpoint（prod のみ、将来対応）

---

## 環境別設定

### dev 環境

- リソース名サフィックス: `-dev`
- Cosmos DB: サーバーレス（コスト最適化）
- Container Apps: 最小レプリカ 0（夜間スケールダウン）
- Log level: Debug

### prod 環境

- リソース名サフィックス: `-prod`
- Cosmos DB: プロビジョニング済み（400 RU/s、オートスケール上限 4000 RU/s）
- Container Apps: 最小レプリカ 1（コールドスタートを防ぐ）
- Log level: Warning

---

## Bicep ファイル構成

```
infra/
├── main.bicep                     # エントリーポイント（全モジュール呼び出し）
├── modules/
│   ├── containerApps.bicep        # Container Apps + 環境
│   ├── cosmosDb.bicep             # Cosmos DB + コンテナ定義
│   ├── keyVault.bicep             # Key Vault + シークレット（空値で作成）
│   ├── containerRegistry.bicep   # Azure Container Registry
│   ├── monitoring.bicep           # Application Insights + Log Analytics
│   └── roleAssignments.bicep      # マネージド ID へのロール割り当て
└── parameters/
    ├── dev.bicepparam             # dev 環境パラメータ
    └── prod.bicepparam            # prod 環境パラメータ
```

---

## デプロイフロー

```
1. Bicep でインフラをプロビジョニング
   az deployment group create --template-file infra/main.bicep \
     --parameters infra/parameters/dev.bicepparam

2. Key Vault にシークレットを手動登録
   （初回のみ。以降は変更時のみ）

3. コンテナイメージをビルドして ACR へプッシュ
   az acr build --registry <acr-name> --image cline-api:latest .

4. Container Apps がACRから最新イメージを取得して自動デプロイ
```

---

## コスト試算（月額概算）

| リソース | dev | prod |
|---|---|---|
| Container Apps | ~$5（夜間スケールゼロ） | ~$30（常時1レプリカ） |
| Cosmos DB | ~$1（サーバーレス、少量使用） | ~$25（400 RU/s） |
| Key Vault | ~$1 | ~$1 |
| Container Registry | ~$5（Basic） | ~$10（Standard） |
| Application Insights | ~$1（少量） | ~$5〜（使用量次第） |
| **合計** | **~$13** | **~$71** |

※ AI Foundry の推論コストは別途（トークン使用量に依存）
