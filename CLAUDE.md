# CLAUDE.md — cline-api-with-az (one-api)

## プロジェクト概要

VS Code + Cline から OpenAI 互換 API 経由で呼び出せる、Azure AI Foundry（gpt-4.1-mini）へのシンプルなプロキシ API システム。
単一の API キーで認証する構成で、メンバーごとの管理・使用量追跡は行わない。
Azure Container Apps 上で動作し、シークレットは Container Apps のネイティブ secrets で管理する。

---

## 技術スタック

| カテゴリ | 技術 |
|---|---|
| 言語 | C# (.NET 8) |
| フレームワーク | ASP.NET Core Web API |
| AI バックエンド | Azure AI Foundry（gpt-4.1-mini） |
| ホスティング | Azure Container Apps |
| 監視 | Azure Application Insights |
| IaC | Bicep（ARM JSON にビルドしてデプロイ） |
| リポジトリ | GitHub |
| テスト | xUnit（ユニットテスト・統合テスト） |

---

## リポジトリ構成

```
cline-api-with-az/
├── CLAUDE.md                  # このファイル
├── README.md                  # プロジェクト概要
│
├── src/
│   └── ClineApiWithAz/        # ASP.NET Core Web API プロジェクト
│       ├── Controllers/       # ChatCompletionsController, ModelsController
│       ├── Services/          # AzureAIService（AI Foundry へのプロキシ）
│       ├── Models/            # リクエスト・レスポンス型
│       ├── Middleware/        # APIキー認証（単一キーとの値比較）
│       ├── Program.cs
│       └── appsettings.json
│
├── tests/
│   ├── ClineApiWithAz.UnitTests/         # ユニットテスト
│   └── ClineApiWithAz.IntegrationTests/  # 統合テスト
│
├── infra/
│   ├── main.bicep             # インフラのエントリーポイント
│   ├── app.bicep              # Container App 本体のデプロイ
│   ├── build.sh               # Bicep → ARM JSON ビルドスクリプト
│   ├── deploy.sh              # デプロイスクリプト
│   ├── destroy.sh             # リソース削除スクリプト
│   ├── arm/                   # ビルド済み ARM JSON（main.json, app.json）
│   ├── modules/               # Bicep モジュール群
│   │   ├── aiFoundry.bicep
│   │   ├── containerApp.bicep
│   │   ├── containerApps.bicep
│   │   ├── containerRegistry.bicep
│   │   ├── managedIdentity.bicep
│   │   ├── monitoring.bicep
│   │   └── roleAssignments.bicep
│   └── parameters/            # 環境別パラメータファイル
│
└── docs/
    ├── architecture.md        # アーキテクチャ設計
    ├── api-spec.md            # API仕様
    ├── infra-design.md        # インフラ設計
    ├── auth.md                # 認証設計
    └── deployment-guide.md    # デプロイ手順
```

---

## 実装状況

すべてのフェーズが完了済み。

- フェーズ 1（設計ドキュメント）: 完了
- フェーズ 2（API サーバー実装）: 完了
- フェーズ 3（テスト実装）: 完了
- フェーズ 4（IaC / Bicep）: 完了

---

## 主要な設計方針

### OpenAI 互換 API
- Cline が標準で対応している OpenAI API 仕様に準拠する
- `/v1/chat/completions`（ストリーミング対応含む）と `/v1/models` を実装
- モデル名はリクエストの `model` フィールドで切り替え可能にする（`appsettings.json` の `AzureAI:Models` でマッピング）

### 認証（単一 API キー方式）
- クライアント（Cline）は `Authorization: Bearer <api-key>` ヘッダーで認証する
- サーバーは `ApiKey:Value`（環境変数 `ApiKey__Value`）と直接比較するだけでよい
- メンバーごとのキー発行・紐付けは行わない
- データベースアクセスなし

### シークレット管理
- `ApiKey__Value`（プロキシ APIキー）と `AzureAI__ApiKey`（AI Foundry APIキー）は Container Apps のネイティブ secrets で管理
- Key Vault は使用しない
- ARM テンプレートの `secureString` パラメータでデプロイ時に渡す

### 監視
- Azure Application Insights でリクエストログ・エラー・レイテンシを収集

### インフラ（Bicep）
- `main.bicep`：AI Foundry、Container Apps 環境、ACR、Managed Identity、監視リソースを構築
- `app.bicep`：Container App 本体（イメージ指定・secrets 設定）を別途デプロイ
- Bicep を変更した場合は `build.sh` を再実行して `arm/` の ARM JSON を更新すること

### エラーハンドリング
- OpenAI API のエラーレスポンス形式に準拠する
- Azure AI Foundry からのエラーは適切にマッピングして返す

---

## コーディング規約

- C# の命名規則は Microsoft の標準に従う（PascalCase、camelCase）
- 非同期処理は `async/await` を使用する
- DIコンテナ（`IServiceCollection`）でサービスを管理する
- 設定値は `appsettings.json` + 環境変数で管理する
- コメントは日本語でOK

---

## ドキュメント規約

- `docs/` 配下の設計ドキュメントは実装と同期を保つ
- インフラ構成を変更する際は `docs/infra-design.md` を先に更新する
- 設計変更があった場合はドキュメントも同時に更新する

---

## 作業時の注意事項

- コードを書く前に、実装内容をユーザーに説明して確認を取る
- Bicep を変更したら必ず `build.sh` で ARM JSON を再生成する
- シークレット（接続文字列、APIキーなど）はコードにハードコードしない
- テストは実装コードと合わせて更新する
