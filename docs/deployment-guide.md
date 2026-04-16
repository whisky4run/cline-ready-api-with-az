# デプロイ手順ガイド

このガイドでは、インフラのプロビジョニングから Cline での動作確認まで、
手動作業が必要なすべての手順を順に説明します。

---

## 前提条件

デプロイを開始する前に以下を準備してください。

### 必須ツール

| ツール | 確認コマンド | インストール先 |
|---|---|---|
| Azure CLI | `az --version` | https://learn.microsoft.com/cli/azure/install-azure-cli |
| Docker | `docker --version` | https://docs.docker.com/get-docker/ |

### Azure の権限

デプロイ対象のサブスクリプションに対して、以下のいずれかのロールが必要です。

- **Owner**（推奨）
- Contributor ＋ User Access Administrator（ロール割り当てに User Access Administrator が必要）

### Azure AI Foundry の準備

デプロイ前に以下を取得しておいてください。

- **エンドポイント URL** — Azure AI Foundry リソースの「推論 URI」  
  例: `https://your-resource.services.ai.azure.com/`
- **API キー** — Azure AI Foundry リソースの「キーと資格情報」から取得

---

## デプロイ手順

### ステップ 1: インフラのプロビジョニング

リポジトリルートから対話型スクリプトを実行します。

```bash
bash infra/deploy.sh
```

スクリプトが以下を対話形式で確認します:

1. サブスクリプションの選択（一覧から選択）
2. リソースグループ名の入力（デフォルト: `rg-cline-api`）
3. 環境の選択（`dev` または `prod`）
4. リージョンの入力（デフォルト: `japaneast`）
5. 設定内容の確認

完了すると以下が表示されます。次のステップで使用するので控えておいてください。

```
  API エンドポイント  : https://ca-cline-api-xxxxxxxx.xxx.japaneast.azurecontainerapps.io
  Key Vault URI       : https://kv-cline-api-xxxxxxxx.vault.azure.net/
  ACR ログインサーバー: acrclineapixxxxxxxx.azurecr.io
  Cosmos DB アカウント: cosmos-cline-api-xxxxxxxx
```

---

### ステップ 2: Key Vault シークレットの登録

Key Vault の名前をまず取得します（スクリプト出力の URI から、または以下のコマンドで確認）。

```bash
az keyvault list --resource-group <RG名> --query "[0].name" --output tsv
```

以下の3つのシークレットを登録します。

#### AzureAI--Endpoint

Azure AI Foundry の推論エンドポイント URL を登録します。

```bash
az keyvault secret set \
  --vault-name <KV名> \
  --name "AzureAI--Endpoint" \
  --value "https://your-resource.services.ai.azure.com/"
```

#### AzureAI--ApiKey

Azure AI Foundry の API キーを登録します。

```bash
az keyvault secret set \
  --vault-name <KV名> \
  --name "AzureAI--ApiKey" \
  --value "<Azure AI Foundry の API キー>"
```

#### CosmosDb--ConnectionString

Cosmos DB の接続文字列を取得して登録します。

```bash
# 接続文字列を取得
COSMOS_CONN=$(az cosmosdb keys list \
  --name <Cosmos DB アカウント名> \
  --resource-group <RG名> \
  --type connection-strings \
  --query "connectionStrings[0].connectionString" \
  --output tsv)

# Key Vault に登録
az keyvault secret set \
  --vault-name <KV名> \
  --name "CosmosDb--ConnectionString" \
  --value "${COSMOS_CONN}"
```

---

### ステップ 3: コンテナイメージのビルドとプッシュ

ACR にログインし、API サーバーのイメージをビルド・プッシュします。

```bash
# ACR のログインサーバー名を変数に設定
ACR_SERVER="acrclineapixxxxxxxx.azurecr.io"  # ステップ1の出力を使用

# ACR へログイン
az acr login --name ${ACR_SERVER%%.*}

# イメージをビルドしてプッシュ（リポジトリルートから実行）
docker build -t ${ACR_SERVER}/cline-api:latest -f src/ClineApiWithAz/Dockerfile .
docker push ${ACR_SERVER}/cline-api:latest
```

> **Dockerfile がない場合の代替手順**  
> Azure Cloud Build を使用することもできます（ローカル Docker 不要）:
>
> ```bash
> az acr build \
>   --registry ${ACR_SERVER%%.*} \
>   --image cline-api:latest \
>   --file src/ClineApiWithAz/Dockerfile \
>   .
> ```

イメージのプッシュ後、Container App が自動的に最新イメージを取得して再起動します。  
再起動状況は以下のコマンドで確認できます。

```bash
az containerapp revision list \
  --name <Container App 名> \
  --resource-group <RG名> \
  --output table
```

---

### ステップ 4: Cosmos DB 初期データの登録

API を利用するには、Cosmos DB に**メンバー情報**と**API キー**を手動で登録する必要があります。  
この操作は初回のみ必要です（以降のメンバー追加時も同様の手順）。

#### 4-1. Entra ID ユーザーの Object ID を確認する

メンバーを登録する前に、対象ユーザーの Entra ID における **Object ID** を取得します。

```bash
# メールアドレスで Object ID を検索
az ad user show --id alice@company.com --query "{name:displayName, oid:id, email:mail}" --output json
```

出力例:
```json
{
  "name": "Alice",
  "oid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "email": "alice@company.com"
}
```

#### 4-2. メンバードキュメントの登録

Azure CLI には Cosmos DB ドキュメントの挿入コマンドがないため、**Azure Portal のデータエクスプローラー**を使用します。

1. [Azure Portal](https://portal.azure.com) を開く
2. 作成した Cosmos DB アカウントに移動
3. 左メニューの **データ エクスプローラー** を開く
4. `ClineApiDb` → `Members` → **Items** を選択
5. ツールバーの **New Item** をクリック
6. 以下の JSON を貼り付けて **Save** をクリック

```json
{
  "id": "member-001",
  "name": "Alice",
  "role": "admin",
  "entraId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "email": "alice@company.com",
  "isActive": true,
  "createdAt": "2026-04-13T00:00:00Z"
}
```

> `entraId` には 4-1 で取得した Object ID を設定してください。

`role` フィールドに設定できる値:

| 値 | 説明 |
|---|---|
| `"admin"` | 管理者。`GET /v1/usage`（全メンバーの使用量参照）が利用可能 |
| `"member"` | 一般メンバー。自分の使用量のみ参照可能 |

#### 4-3. API キーのハッシュ化

API キーはデータベースに**平文で保存しません**。SHA-256 ハッシュ値を登録します。  
まず、メンバーに配布する生の API キーを決めて、そのハッシュ値を計算します。

```bash
# 生のキーを決める（例: sk-alice-<ランダム文字列>）
RAW_KEY="sk-alice-$(openssl rand -hex 16)"
echo "生のキー（メンバーに配布する値）: ${RAW_KEY}"

# SHA-256 ハッシュを計算（macOS）
KEY_HASH=$(echo -n "${RAW_KEY}" | shasum -a 256 | awk '{print $1}')

# SHA-256 ハッシュを計算（Linux）
# KEY_HASH=$(echo -n "${RAW_KEY}" | sha256sum | awk '{print $1}')

echo "ハッシュ値（Cosmos DB に登録する値）: ${KEY_HASH}"
```

> **重要**: 生の API キー（`RAW_KEY`）はこのタイミングにしか確認できません。  
> メンバーに安全な手段で伝えた後、ハッシュ値のみを Cosmos DB に保存します。

#### 4-4. API キードキュメントの登録

同じく **Azure Portal のデータエクスプローラー** を使用します。

1. `ClineApiDb` → `ApiKeys` → **Items** を選択
2. **New Item** をクリック
3. 以下の JSON を貼り付けて **Save** をクリック

```json
{
  "id": "<uuidgen などで生成した UUID>",
  "memberId": "member-001",
  "keyHash": "<4-3 で計算した KEY_HASH の値>",
  "prefix": "sk-alice-",
  "isActive": true,
  "createdAt": "<現在日時を ISO 8601 形式で。例: 2026-04-16T00:00:00Z>"
}
```

> `memberId` の値は、ステップ 4-1 で登録したメンバーの `id` と一致させてください。

---

### ステップ 5: Cline の設定

VS Code の Cline 拡張機能を以下のように設定します。

| 設定項目 | 値 |
|---|---|
| API Provider | `OpenAI Compatible` |
| Base URL | `https://<Container App の FQDN>/v1` |
| API Key | ステップ 4-2 で生成した生のキー（`RAW_KEY`） |
| Model | `gpt-4.1-mini` |

FQDN はステップ 1 の出力（`API エンドポイント`）から確認できます。  
または以下のコマンドで取得できます:

```bash
az containerapp show \
  --name <Container App 名> \
  --resource-group <RG名> \
  --query "properties.configuration.ingress.fqdn" \
  --output tsv
```

---

## 動作確認

以下の curl コマンドで API が正常に動作していることを確認します。

### モデル一覧の取得

```bash
curl -s \
  -H "Authorization: Bearer ${RAW_KEY}" \
  https://<FQDN>/v1/models | jq .
```

期待するレスポンス:

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

### チャット補完の確認

```bash
curl -s -X POST \
  -H "Authorization: Bearer ${RAW_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"Hello!"}]}' \
  https://<FQDN>/v1/chat/completions | jq .choices[0].message.content
```

---

## リソースの削除

環境を削除するには以下を実行します。

```bash
bash infra/destroy.sh
```

スクリプトが削除対象のリソース一覧を表示し、リソースグループ名の再入力で確認後に削除します。

> **Key Vault のソフト削除について**  
> Key Vault は削除後も 7 日間ソフト削除状態で残ります。  
> 同名の Key Vault を再作成したい場合は、スクリプト完了後に表示される  
> `az keyvault purge` コマンドを実行してください。

---

## トラブルシューティング

### Container App が起動しない

Container App のシステムログを確認します:

```bash
az containerapp logs show \
  --name <Container App 名> \
  --resource-group <RG名> \
  --type system \
  --output table
```

コンテナのログを確認します:

```bash
az containerapp logs show \
  --name <Container App 名> \
  --resource-group <RG名> \
  --output table \
  --tail 50
```

### Key Vault シークレットが取得できない

マネージド ID に `Key Vault Secrets User` ロールが付与されているか確認します:

```bash
az role assignment list \
  --scope $(az keyvault show --name <KV名> --query id --output tsv) \
  --output table
```

### Cosmos DB に接続できない

マネージド ID に Cosmos DB の SQL ロールが付与されているか確認します:

```bash
az cosmosdb sql role assignment list \
  --account-name <Cosmos DB アカウント名> \
  --resource-group <RG名> \
  --output table
```

### ACR からイメージをプルできない

マネージド ID に `AcrPull` ロールが付与されているか確認します:

```bash
az role assignment list \
  --scope $(az acr show --name <ACR名> --query id --output tsv) \
  --output table
```
