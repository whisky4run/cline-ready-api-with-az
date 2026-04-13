# CLAUDE.md — cline-api-with-az

## プロジェクト概要

VS Code + Cline から OpenAI 互換 API 経由で呼び出せる、Azure AI Foundry（GPT-5系）へのプロキシ API システム。
メンバーごとの API キー認証と使用量管理を備え、Azure 上で動作する。

---

## 技術スタック

| カテゴリ | 技術 |
|---|---|
| 言語 | C# (.NET 9以降) |
| フレームワーク | ASP.NET Core Web API |
| AI バックエンド | Azure AI Foundry（GPT-5系モデル） |
| インフラ | Azure（構成はフェーズ2で決定） |
| IaC | Bicep |
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
│       ├── Controllers/       # APIエンドポイント
│       ├── Services/          # ビジネスロジック（AI呼び出し、使用量管理など）
│       ├── Models/            # リクエスト・レスポンス型、ドメインモデル
│       ├── Middleware/        # APIキー認証など
│       ├── Program.cs
│       └── appsettings.json
│
├── tests/
│   ├── ClineApiWithAz.UnitTests/       # ユニットテスト
│   └── ClineApiWithAz.IntegrationTests/ # 統合テスト
│
├── infra/
│   ├── main.bicep             # エントリーポイント
│   ├── modules/               # Bicep モジュール群
│   └── parameters/            # 環境別パラメータファイル
│
└── docs/
    ├── architecture.md        # アーキテクチャ設計
    ├── api-spec.md            # API仕様
    ├── infra-design.md        # インフラ設計
    └── usage-tracking.md      # 使用量管理の設計
```

---

## 開発フェーズ

### フェーズ 1：設計ドキュメント作成
- `docs/architecture.md` — システム全体のアーキテクチャ設計を記述
- `docs/api-spec.md` — OpenAI 互換 API の仕様を定義
- `docs/infra-design.md` — Azure リソース構成の設計を記述
- `docs/usage-tracking.md` — メンバーごとの使用量管理の設計を記述

### フェーズ 2：API サーバー実装（C#）
- ASP.NET Core プロジェクトのセットアップ
- OpenAI 互換エンドポイントの実装（`/v1/chat/completions` など）
- Azure AI Foundry への接続・モデル切り替え対応
- APIキー認証ミドルウェアの実装
- メンバーごとの使用量記録・参照機能の実装

### フェーズ 3：テスト実装
- ユニットテスト（Services、Middleware）
- 統合テスト（エンドポイント全体の動作確認）

### フェーズ 4：IaC（Bicep）
- Azure リソースの Bicep 定義
- 環境別パラメータ（dev / prod）

---

## 主要な設計方針

### OpenAI 互換 API
- Cline が標準で対応している OpenAI API 仕様に準拠する
- 最低限 `/v1/chat/completions`（ストリーミング対応含む）を実装する
- モデル名はリクエストの `model` フィールドで切り替え可能にする

### 認証（APIキー方式）
- クライアント（Cline）は `Authorization: Bearer <api-key>` ヘッダーで認証する
- APIキーはメンバーごとに発行・管理する
- APIキーと利用者の紐付けはサーバー側で管理する

### 使用量管理
- リクエスト・レスポンスのトークン数をメンバーごとに記録する
- 使用量の参照 API を用意する（管理者向け）
- ストレージは Azure のマネージドサービスを利用（詳細はフェーズ1で設計）

### モデル切り替え
- リクエストの `model` フィールドに応じて AI Foundry のモデルを切り替える
- 利用可能なモデルは設定ファイルで管理する

### エラーハンドリング
- OpenAI API のエラーレスポンス形式に準拠する
- Azure AI Foundry からのエラーは適切にマッピングして返す

---

## コーディング規約

- C# の命名規則は Microsoft の標準に従う（PascalCase、camelCase）
- 非同期処理は `async/await` を使用する
- DIコンテナ（`IServiceCollection`）でサービスを管理する
- 設定値は `appsettings.json` + 環境変数で管理し、シークレットはAzure Key Vaultを使用する
- コメントは日本語でOK

---

## ドキュメント規約

- `docs/` 配下の設計ドキュメントは実装前に作成し、実装と同期を保つ
- Bicep を書く前に `docs/infra-design.md` に設計を記述してから実装する
- 設計変更があった場合はドキュメントも同時に更新する

---

## 作業時の注意事項

- 各フェーズは順番に進める。前のフェーズが完了してから次に進む
- コードを書く前に、実装内容をユーザーに説明して確認を取る
- Bicep のリソース構成を変更する際は `docs/infra-design.md` を先に更新する
- シークレット（接続文字列、APIキーなど）はコードにハードコードしない
- `tests/` のテストは実装コードと同じフェーズで作成する（後回しにしない）
