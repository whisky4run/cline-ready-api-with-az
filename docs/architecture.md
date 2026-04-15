# アーキテクチャ設計

## システム概要

VS Code の Cline 拡張から OpenAI 互換 API 経由でリクエストを受け取り、Azure AI Foundry（gpt-4.1-mini）へプロキシするシステム。
メンバーごとの API キー認証と使用量管理を備える。

---

## コンポーネント構成

```
┌─────────────────────────────────────────────────────────────────┐
│ クライアント環境（開発者 PC）                                        │
│  VS Code + Cline 拡張                                            │
│    │  Authorization: Bearer <member-api-key>                     │
│    │  POST /v1/chat/completions                                   │
└────┼────────────────────────────────────────────────────────────┘
     │ HTTPS
     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Azure（プロキシ API）                                              │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │ ASP.NET Core Web API                                      │    │
│  │                                                           │    │
│  │  [Middleware]                                             │    │
│  │   APIキー認証 → レート制限（将来）                           │    │
│  │                                                           │    │
│  │  [Controllers]                                            │    │
│  │   ChatCompletionsController  GET /v1/models               │    │
│  │   ModelsController           GET /v1/usage（管理者向け）    │    │
│  │   UsageController                                         │    │
│  │                                                           │    │
│  │  [Services]                                               │    │
│  │   AzureAIService    ── Azure AI Foundry へ転送             │    │
│  │   UsageService      ── トークン使用量の記録・集計            │    │
│  │   ApiKeyService     ── APIキーの検証・メンバー紐付け         │    │
│  └──────────────────────────────────────────────────────────┘    │
│          │                          │                             │
│          ▼                          ▼                             │
│  ┌───────────────┐        ┌──────────────────┐                   │
│  │ Azure AI      │        │ Azure Cosmos DB   │                   │
│  │ Foundry       │        │（使用量・APIキー） │                   │
│  │（GPT-5系）    │        └──────────────────┘                   │
│  └───────────────┘                                                │
│                                                                   │
│  ┌───────────────┐        ┌──────────────────┐                   │
│  │ Azure Key     │        │ Azure Application │                   │
│  │ Vault         │        │ Insights          │                   │
│  │（シークレット）│        │（監視・ログ）     │                   │
│  └───────────────┘        └──────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## リクエストフロー

### チャット補完リクエスト（ストリーミングあり）

```
Cline
  │
  │ POST /v1/chat/completions
  │ Authorization: Bearer <member-api-key>
  │ { "model": "gpt-5", "messages": [...], "stream": true }
  ▼
APIキー認証ミドルウェア
  │ APIキーを検証 → メンバーIDを特定
  │ 無効なら 401 Unauthorized を返す
  ▼
ChatCompletionsController
  │
  ├─→ UsageService（リクエスト開始を記録）
  │
  ├─→ AzureAIService
  │     │ モデル名（`gpt-4.1-mini`）を AI Foundry のデプロイ URI にマッピング
  │     │ Azure AI Foundry へリクエスト転送
  │     │ ストリーミングレスポンスを受信
  │     ▼
  │   SSE（Server-Sent Events）でクライアントへ転送
  │
  └─→ UsageService（レスポンス完了後にトークン数を記録）
```

---

## 主要コンポーネント詳細

### APIキー認証ミドルウェア

- `Authorization: Bearer <api-key>` ヘッダーを検証
- APIキーに紐付くメンバー情報を取得し、`HttpContext.Items` に格納
- 無効・未指定の場合は `401 Unauthorized` を返す（OpenAI 互換エラー形式）
- APIキーは Cosmos DB で管理し、Key Vault からは接続文字列のみ取得

### AzureAIService

- Azure AI Foundry の推論エンドポイントへ HTTP リクエストを送信
- モデル名のマッピング（例: `"gpt-4.1-mini"` → `azureml://registries/azure-openai/models/gpt-4.1-mini/versions/2025-04-14`）
- ストリーミング（SSE）・非ストリーミング両対応
- Azure AI Foundry からのエラーを OpenAI 互換エラー形式にマッピング

### UsageService

- リクエストごとのトークン使用量（prompt_tokens / completion_tokens）を Cosmos DB に記録
- メンバーIDと日時でインデックス化
- 集計クエリ（日別・月別）を提供

### ApiKeyService

- APIキーの検証（ハッシュ比較）
- メンバー情報（ID、名前、権限）の取得
- APIキーの発行・無効化（管理 API 経由）

---

## 非機能要件

| 項目 | 方針 |
|---|---|
| 認証 | APIキー（Bearer トークン）方式 |
| シークレット管理 | Azure Key Vault（接続文字列、AI Foundry エンドポイント・キー） |
| ログ・監視 | Azure Application Insights（リクエストログ、エラー、レイテンシ） |
| スケーリング | Azure Container Apps（オートスケール対応） |
| 可用性 | Azure のマネージドサービスに依存 |
| セキュリティ | HTTPS 強制、APIキーは SHA-256 ハッシュで保存 |

---

## 技術スタック

| カテゴリ | 採用技術 |
|---|---|
| 言語 / FW | C# / ASP.NET Core Web API (.NET 9) |
| AI バックエンド | Azure AI Foundry（gpt-4.1-mini） |
| DB | Azure Cosmos DB（NoSQL、サーバーレス） |
| シークレット | Azure Key Vault |
| ホスティング | Azure Container Apps |
| 監視 | Azure Application Insights |
| IaC | Bicep |
