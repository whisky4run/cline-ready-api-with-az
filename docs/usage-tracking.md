# 使用量管理設計

## 概要

メンバーごとの API 使用量（トークン数・リクエスト数）を記録・集計する仕組み。
ストレージは Azure Cosmos DB（NoSQL）を使用し、リクエスト完了時に非同期で記録する。

---

## データモデル

### UsageRecord（使用量レコード）

1リクエスト = 1ドキュメント

```json
{
  "id": "uuid-v4",
  "memberId": "member-001",
  "requestedAt": "2026-04-13T10:00:00Z",
  "model": "gpt-4.1-mini",
  "promptTokens": 150,
  "completionTokens": 80,
  "totalTokens": 230,
  "durationMs": 1250,
  "statusCode": 200
}
```

| フィールド | 型 | 説明 |
|---|---|---|
| id | string | UUID v4（Cosmos DB ドキュメント ID） |
| memberId | string | メンバー識別子（パーティションキー） |
| requestedAt | string | リクエスト日時（ISO 8601 UTC） |
| model | string | 使用したモデル名 |
| promptTokens | integer | プロンプトのトークン数 |
| completionTokens | integer | 生成されたトークン数 |
| totalTokens | integer | 合計トークン数 |
| durationMs | integer | リクエスト処理時間（ミリ秒） |
| statusCode | integer | HTTP ステータスコード |

### Member（メンバー）

```json
{
  "id": "member-001",
  "name": "Alice",
  "role": "member",
  "isActive": true,
  "createdAt": "2026-01-01T00:00:00Z"
}
```

| フィールド | 型 | 説明 |
|---|---|---|
| id | string | メンバー識別子 |
| name | string | 表示名 |
| role | string | `"member"` または `"admin"` |
| isActive | boolean | 有効フラグ |
| createdAt | string | 登録日時 |

### ApiKey（APIキー）

```json
{
  "id": "key-abc123",
  "memberId": "member-001",
  "keyHash": "sha256-hash-of-the-api-key",
  "prefix": "sk-alice-",
  "isActive": true,
  "createdAt": "2026-01-01T00:00:00Z",
  "lastUsedAt": "2026-04-13T09:55:00Z"
}
```

| フィールド | 型 | 説明 |
|---|---|---|
| id | string | APIキー識別子 |
| memberId | string | 紐付くメンバーID（パーティションキー） |
| keyHash | string | APIキーの SHA-256 ハッシュ（生のキーは保存しない） |
| prefix | string | 識別用プレフィックス（例: `sk-alice-`） |
| isActive | boolean | 有効フラグ |
| createdAt | string | 発行日時 |
| lastUsedAt | string | 最終使用日時 |

---

## 使用量の記録フロー

```
1. チャット補完リクエスト受信
     ↓
2. APIキー認証 → memberId を特定
     ↓
3. Azure AI Foundry へリクエスト転送（ストリーミングまたは通常）
     ↓
4. レスポンス完了（ストリーミング終了 or 通常レスポンス受信）
     ↓
5. レスポンスの usage フィールドからトークン数を取得
     ↓
6. UsageRecord を Cosmos DB に書き込み（非同期・fire-and-forget）
     ↓
7. クライアントへレスポンスを返す（書き込み完了を待たない）
```

### 注意事項

- ストリーミングの場合、トークン数は最終チャンク（`finish_reason: "stop"` 時）に含まれる `usage` フィールドから取得する
- Azure AI Foundry がトークン数を返さない場合（レスポンスが不正等）は、`promptTokens = 0, completionTokens = 0` として記録する
- Cosmos DB への書き込み失敗はログに記録するが、クライアントへのレスポンスには影響させない

---

## 使用量の集計

集計はクエリ時に Cosmos DB への SQL クエリで行う（事前集計なし）。

### クエリ例（月別集計）

```sql
SELECT
  c.memberId,
  SUM(c.promptTokens) AS totalPromptTokens,
  SUM(c.completionTokens) AS totalCompletionTokens,
  SUM(c.totalTokens) AS totalTokens,
  COUNT(1) AS requestCount
FROM c
WHERE c.memberId = @memberId
  AND c.requestedAt >= @from
  AND c.requestedAt <= @to
GROUP BY c.memberId
```

- 大量データになった場合は、日次サマリードキュメントを別途生成することを検討する（将来対応）

---

## APIキー管理

### 発行フロー

1. 管理者が管理 API（将来実装）またはスクリプトでメンバーを登録
2. ランダムな 32 バイトの APIキーを生成（例: `sk-alice-xxxxxxxxxxxxxxxx`）
3. SHA-256 ハッシュを Cosmos DB の `ApiKeys` コンテナに保存
4. 生のAPIキーを管理者に伝達（以降は参照不可）

### 認証フロー

1. リクエストの `Authorization: Bearer <api-key>` ヘッダーからキーを取得
2. キーの SHA-256 ハッシュを計算
3. Cosmos DB でハッシュが一致する有効な `ApiKey` ドキュメントを検索
4. 見つかれば `memberId` を取得し認証成功
5. `ApiKey.lastUsedAt` を更新（非同期）

### セキュリティ方針

- 生のAPIキーはサーバー側に保存しない（ハッシュのみ保存）
- APIキーの送信は HTTPS のみ
- APIキーを無効化したい場合は `isActive: false` に更新する（物理削除しない）

---

## 将来の拡張（フェーズ 2 以降で検討）

| 機能 | 説明 |
|---|---|
| 使用量上限設定 | メンバーごとの月間トークン上限を設定し、超過時は 429 を返す |
| レート制限 | 単位時間あたりのリクエスト数を制限 |
| 通知 | 上限の 80% に達したらメールや Slack で通知 |
| ダッシュボード | 使用量の可視化（Azure Workbooks または外部ツール） |
| 日次サマリー | 集計コストを下げるため、日次サマリードキュメントをバッチ生成 |
