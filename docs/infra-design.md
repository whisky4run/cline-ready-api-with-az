# インフラ設計

## 概要

Azure 上で動作するプロキシ API システムのインフラ構成。
IaC は Bicep で管理するが、デプロイは Bicep を ARM JSON にビルドした上で ARM テンプレートで行う。
dev / prod の 2 環境を用意する。

---

## Azure リソース構成

```
リソースグループ（既存。AI Foundry と共用）
│
├── Azure Container Apps（API ホスティング）
│     ca-cline-api-{suffix}
│
├── Azure Container Apps 環境
│     cae-cline-api-{suffix}
│
├── Azure Container Registry（コンテナイメージ）
│     acrclineapi{suffix}
│
├── Azure Application Insights（監視）
│     appi-cline-api-{suffix}
│
├── Azure Log Analytics Workspace
│     law-cline-api-{suffix}
│
└── ユーザー割り当てマネージド ID（UAMI）
      id-cline-api-{suffix}
```

> `{suffix}` はリソースグループ ID から生成される 8 文字の一意サフィックス（同一 RG で冪等）。  
> Cosmos DB・Key Vault は使用しない。

---

## 各リソースの詳細

### Azure Container Apps

| 項目 | dev | prod |
|---|---|---|
| CPU | 0.5 vCPU | 1.0 vCPU |
| メモリ | 1.0 Gi | 2.0 Gi |
| 最小レプリカ数 | 0（夜間スケールダウン） | 1 |
| 最大レプリカ数 | 3 | 10 |
| スケールルール | HTTP 同時接続数（閾値: 100） | 同左 |
| イングレス | 外部公開（HTTPS） | 外部公開（HTTPS） |

シークレットは Container Apps のネイティブ secrets 機能で管理する。

| シークレット名（CA内） | 環境変数名 | 内容 |
|---|---|---|
| `azure-ai-api-key` | `AzureAI__ApiKey` | Azure AI Foundry の API キー |
| `api-key-value` | `ApiKey__Value` | Cline からの認証に使う API キー |

その他の環境変数（非シークレット）:

| 環境変数名 | 内容 |
|---|---|
| `AzureAI__Endpoint` | Azure AI Foundry のエンドポイント URL |
| `ApplicationInsights__ConnectionString` | Application Insights 接続文字列 |
| `ASPNETCORE_ENVIRONMENT` | `Development`（dev）/ `Production`（prod） |

### Azure Container Registry

- SKU: Basic（dev）/ Standard（prod）
- 管理者アカウント: 無効（UAMI の AcrPull ロールでプル）

### Azure Application Insights

- サンプリング率: 100%（dev）/ 10%（prod）
- Log Analytics Workspace と連携

### ユーザー割り当てマネージド ID（UAMI）

- Container App のコンテナ実行 ID として使用
- 付与ロール: `AcrPull`（ACR からのイメージ取得のみ）

---

## ネットワーク設計

- Container Apps のイングレスは HTTPS のみ（Container Apps が自動で TLS 終端）
- IP 制限なし（API キー認証で保護）
- dev / prod ともに同一構成

---

## Bicep / ARM ファイル構成

```
infra/
├── main.bicep                     # フェーズ1: インフラ構築エントリーポイント
├── app.bicep                      # フェーズ2: Container App デプロイ
├── arm/                           # build.sh で生成した ARM JSON（コミット対象）
│   ├── main.json                  # main.bicep のコンパイル済み ARM テンプレート
│   └── app.json                   # app.bicep のコンパイル済み ARM テンプレート
├── modules/
│   ├── containerApps.bicep        # Container Apps 環境
│   ├── containerApp.bicep         # Container App 本体（secrets/env var 注入）
│   ├── containerRegistry.bicep    # Azure Container Registry
│   ├── monitoring.bicep           # Application Insights + Log Analytics
│   ├── managedIdentity.bicep      # ユーザー割り当てマネージド ID
│   └── roleAssignments.bicep      # UAMI への AcrPull ロール割り当て
├── parameters/
│   ├── dev.bicepparam             # dev 環境パラメータ（env, location）
│   └── prod.bicepparam            # prod 環境パラメータ（env, location）
├── build.sh                       # Bicep → ARM JSON 変換スクリプト
├── deploy.sh                      # 対話型デプロイスクリプト（ARM 使用）
└── destroy.sh                     # タグ付きリソース削除スクリプト
```

---

## デプロイフロー

```
【Bicep を変更したとき（初回含む）】
  bash infra/build.sh
  → infra/arm/main.json, infra/arm/app.json を再生成
  → git add infra/arm/ && git commit

【毎回のデプロイ】
  bash infra/deploy.sh
    1. 対話入力（サブスクリプション、RG、AI Foundry、プロキシ API キー、環境）
    2. arm/main.json をデプロイ（ACR・CA 環境・UAMI・監視）
    3. Docker イメージをビルドして ACR へプッシュ
    4. UAMI ロール伝播待機（90秒）
    5. arm/app.json をデプロイ（Container App、secrets を --parameters で渡す）
```

シークレット（`azureAiApiKey`, `apiKeyValue`）は ARM テンプレートの `secureString` パラメータとして渡すため、デプロイ履歴に残らない。

---

## コスト試算（月額概算）

| リソース | dev | prod |
|---|---|---|
| Container Apps | ~$5（夜間スケールゼロ） | ~$30（常時1レプリカ） |
| Container Registry | ~$5（Basic） | ~$10（Standard） |
| Application Insights | ~$1（少量） | ~$5〜（使用量次第） |
| **合計** | **~$11** | **~$45** |

※ AI Foundry の推論コストは別途（トークン使用量に依存）  
※ Cosmos DB・Key Vault を廃止したことで main ブランチより ~$26/月（dev）削減
