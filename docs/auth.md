# 認証設計

## 概要

単一の API キーによる Bearer トークン認証。ユーザー特定・使用量管理は行わない。
API キーはデプロイ時に設定し、Container App の secrets として管理する。

---

## 認証フロー

```
1. クライアント（Cline）がリクエストを送信
     Authorization: Bearer <api-key>
     ↓
2. ApiKeyAuthMiddleware がヘッダーを検証
     - Authorization ヘッダーが存在するか確認
     - "Bearer " プレフィックスがあるか確認
     - 値が環境変数 ApiKey__Value と一致するか確認
     ↓
3a. 一致した場合 → 次のミドルウェア（Controller）へ進む
3b. 不一致・未指定の場合 → 401 Unauthorized を返す
```

---

## API キーの管理

### 設定方法

API キーは以下の優先順位で解決される。

| 優先度 | 設定方法 | 用途 |
|---|---|---|
| 高 | 環境変数 `ApiKey__Value` | 本番デプロイ（Container App secrets から注入） |
| 低 | `appsettings.json` の `ApiKey.Value` | ローカル開発 |

### ローカル開発時の設定

`src/ClineApiWithAz/appsettings.Development.json` を作成して設定する（git 管理外）。

```json
{
  "ApiKey": {
    "Value": "sk-dev-local-test"
  },
  "AzureAI": {
    "Endpoint": "https://your-resource.services.ai.azure.com/",
    "ApiKey": "your-azure-ai-key"
  }
}
```

### 本番デプロイ時の設定

`deploy.sh` の対話入力でプロキシ API キーを入力する。  
スクリプトが ARM テンプレートの `apiKeyValue` パラメータ（`secureString`）として渡し、
Container App の secrets に保存される。

デプロイ履歴には残らない。

---

## API キーの更新手順

API キーを変更したい場合、`deploy.sh` を再実行して新しいキーを入力するだけでよい。  
Container App の secrets が更新され、新しいリビジョンが自動的にデプロイされる。

または Azure CLI で直接更新することもできる。

```bash
az containerapp secret set \
  --name <Container App 名> \
  --resource-group <RG名> \
  --secrets api-key-value=<新しいキー>

az containerapp update \
  --name <Container App 名> \
  --resource-group <RG名> \
  --set-env-vars ApiKey__Value=secretref:api-key-value
```

---

## セキュリティ方針

- API キーの送信は HTTPS のみ（Container Apps が自動で TLS 終端）
- API キーの値はコードにハードコードしない
- `appsettings.json` の `ApiKey.Value` はデフォルト空文字。本番では環境変数で必ず上書きされる
- ARM デプロイ時のパラメータは `secureString` 型のため、Azure のデプロイ履歴に値が記録されない

---

## 複数ユーザーへの対応

本ブランチ（one-api）は単一キーの共有運用を想定している。  
ユーザー単位の API キー管理・使用量追跡が必要な場合は `main` ブランチを参照すること。
