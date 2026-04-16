# アーキテクチャ設計

## システム概要

VS Code の Cline 拡張から OpenAI 互換 API 経由でリクエストを受け取り、Azure AI Foundry（gpt-4.1-mini）へプロキシするシステム。
単一の API キーで認証し、ユーザー特定・使用量管理は行わないシンプルな構成。

---

## コンポーネント構成

```
┌─────────────────────────────────────────────────────────────────┐
│ クライアント環境（開発者 PC）                                        │
│  VS Code + Cline 拡張                                            │
│    │  Authorization: Bearer <api-key>                            │
│    │  POST /v1/chat/completions                                   │
└────┼────────────────────────────────────────────────────────────┘
     │ HTTPS
     ▼
┌─────────────────────────────────────────────────────────────────┐
│ Azure（プロキシ API）                                              │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐    │
│  │ ASP.NET Core Web API（Azure Container Apps）              │    │
│  │                                                           │    │
│  │  [Middleware]                                             │    │
│  │   APIキー認証（設定値との単純比較）                          │    │
│  │                                                           │    │
│  │  [Controllers]                                            │    │
│  │   ChatCompletionsController  POST /v1/chat/completions    │    │
│  │   ModelsController           GET  /v1/models              │    │
│  │                                                           │    │
│  │  [Services]                                               │    │
│  │   AzureAIService  ── Azure AI Foundry へ転送              │    │
│  └──────────────────────────────────────────────────────────┘    │
│          │                                                        │
│          ▼                                                        │
│  ┌───────────────┐        ┌──────────────────┐                   │
│  │ Azure AI      │        │ Azure Application │                   │
│  │ Foundry       │        │ Insights          │                   │
│  │（gpt-4.1-mini）│        │（監視・ログ）     │                   │
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
  │ Authorization: Bearer <api-key>
  │ { "model": "gpt-4.1-mini", "messages": [...], "stream": true }
  ▼
APIキー認証ミドルウェア
  │ appsettings（または環境変数）の ApiKey:Value と比較
  │ 不一致なら 401 Unauthorized を返す
  ▼
ChatCompletionsController
  │
  └─→ AzureAIService
        │ モデル名（`gpt-4.1-mini`）を AI Foundry のデプロイ URI にマッピング
        │ Azure AI Foundry へリクエスト転送
        │ ストリーミングレスポンスを受信
        ▼
      SSE（Server-Sent Events）でクライアントへ転送
```

---

## 主要コンポーネント詳細

### APIキー認証ミドルウェア

- `Authorization: Bearer <api-key>` ヘッダーを検証
- 環境変数 `ApiKey__Value`（または `appsettings.json` の `ApiKey:Value`）と直接比較
- 不一致・未指定の場合は `401 Unauthorized` を返す（OpenAI 互換エラー形式）
- データベースアクセスなし。シークレットは Container App の secrets 機能で管理

### AzureAIService

- Azure AI Foundry の推論エンドポイントへ HTTP リクエストを送信
- モデル名のマッピング（例: `"gpt-4.1-mini"` → `azureml://registries/azure-openai/models/gpt-4.1-mini/versions/2025-04-14`）
- ストリーミング（SSE）・非ストリーミング両対応
- Azure AI Foundry からのエラーを OpenAI 互換エラー形式にマッピング

---

## 非機能要件

| 項目 | 方針 |
|---|---|
| 認証 | 単一 API キー（Bearer トークン）の値比較 |
| シークレット管理 | Container Apps のネイティブ secrets（`ApiKey__Value`, `AzureAI__ApiKey`） |
| ログ・監視 | Azure Application Insights（リクエストログ、エラー、レイテンシ） |
| スケーリング | Azure Container Apps（オートスケール対応） |
| 可用性 | Azure のマネージドサービスに依存 |
| セキュリティ | HTTPS 強制、シークレットは ARM テンプレートの secureString パラメータで渡す |

---

## 技術スタック

| カテゴリ | 採用技術 |
|---|---|
| 言語 / FW | C# / ASP.NET Core Web API (.NET 8) |
| AI バックエンド | Azure AI Foundry（gpt-4.1-mini） |
| ホスティング | Azure Container Apps |
| 監視 | Azure Application Insights |
| IaC | Bicep（ARM JSON にビルドしてデプロイ） |
