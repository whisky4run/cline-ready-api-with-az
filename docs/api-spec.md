# API 仕様

## 概要

OpenAI API 仕様に準拠したプロキシ API。Cline が標準対応している形式でリクエストを受け付け、Azure AI Foundry へ転送する。

ベース URL: `https://<host>/v1`

---

## 認証

すべてのエンドポイントで API キー認証が必要。

```
Authorization: Bearer <api-key>
```

- 認証失敗時は `401 Unauthorized` を返す
- API キーはデプロイ時に設定した単一の値で認証する（ユーザー単位の管理なし）

---

## エンドポイント一覧

| メソッド | パス | 説明 |
|---|---|---|
| POST | /v1/chat/completions | チャット補完 |
| GET | /v1/models | 利用可能なモデル一覧 |

---

## POST /v1/chat/completions

### リクエスト

```http
POST /v1/chat/completions
Authorization: Bearer <api-key>
Content-Type: application/json
```

```json
{
  "model": "gpt-4.1-mini",
  "messages": [
    { "role": "system", "content": "You are a helpful assistant." },
    { "role": "user", "content": "Hello!" }
  ],
  "stream": false,
  "temperature": 1.0,
  "max_tokens": 4096,
  "top_p": 1.0,
  "frequency_penalty": 0.0,
  "presence_penalty": 0.0
}
```

| フィールド | 型 | 必須 | 説明 |
|---|---|---|---|
| model | string | ○ | モデル名（設定で定義されたものに限る） |
| messages | array | ○ | チャット履歴 |
| stream | boolean | - | ストリーミング有無（デフォルト: false） |
| temperature | number | - | サンプリング温度（0.0〜2.0） |
| max_tokens | integer | - | 最大生成トークン数 |
| top_p | number | - | Top-p サンプリング |
| frequency_penalty | number | - | 頻度ペナルティ |
| presence_penalty | number | - | 存在ペナルティ |

### レスポンス（stream: false）

```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1700000000,
  "model": "gpt-4.1-mini",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help you?"
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 10,
    "total_tokens": 30
  }
}
```

### レスポンス（stream: true）

`Content-Type: text/event-stream` で Server-Sent Events を返す。

```
data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1700000000,"model":"gpt-4.1-mini","choices":[{"index":0,"delta":{"role":"assistant","content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1700000000,"model":"gpt-4.1-mini","choices":[{"index":0,"delta":{"content":"!"},"finish_reason":null}]}

data: {"id":"chatcmpl-abc123","object":"chat.completion.chunk","created":1700000000,"model":"gpt-4.1-mini","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

---

## GET /v1/models

利用可能なモデルの一覧を返す。

### レスポンス

```json
{
  "object": "list",
  "data": [
    {
      "id": "gpt-4.1-mini",
      "object": "model",
      "created": 1744588800,
      "owned_by": "azure-ai-foundry"
    }
  ]
}
```

---

## エラーレスポンス

OpenAI API のエラー形式に準拠する。

```json
{
  "error": {
    "message": "Invalid API key.",
    "type": "invalid_request_error",
    "code": "invalid_api_key"
  }
}
```

### エラーコード一覧

| HTTP ステータス | type | code | 説明 |
|---|---|---|---|
| 400 | invalid_request_error | invalid_request | リクエスト形式が不正 |
| 400 | invalid_request_error | model_not_found | 指定モデルが設定に存在しない |
| 401 | invalid_request_error | invalid_api_key | APIキーが無効または未指定 |
| 502 | api_error | upstream_error | Azure AI Foundry からのエラー |

---

## モデルマッピング設定

`appsettings.json` でモデル名と AI Foundry デプロイ URI をマッピングする。

```json
{
  "AzureAI": {
    "Models": {
      "gpt-4.1-mini": "gpt-4.1-mini"
    }
  }
}
```

モデルを追加する場合はこのマッピングにエントリを追加してイメージを再ビルドする。
