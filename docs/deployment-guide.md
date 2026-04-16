# デプロイ手順ガイド

インフラのプロビジョニングから Cline での動作確認まで、手順を順に説明します。

---

## 前提条件

### 必須ツール

| ツール | 確認コマンド | インストール先 |
|---|---|---|
| Azure CLI | `az --version` | https://learn.microsoft.com/cli/azure/install-azure-cli |
| Docker | `docker --version` | https://docs.docker.com/get-docker/ |

> Bicep CLI はデプロイ環境には不要（ARM JSON をリポジトリにコミット済み）。  
> Bicep ファイルを変更した場合のみ `build.sh` の実行が必要（後述）。

### Azure の権限

デプロイ対象のサブスクリプションに対して、以下のいずれかのロールが必要。

- **Owner**（推奨）
- Contributor ＋ User Access Administrator

### Azure AI Foundry の準備

デプロイ前に対象のリソースグループに Azure AI Foundry（Cognitive Services）アカウントが作成済みであること。  
エンドポイントと API キーはデプロイスクリプトが自動取得する。

---

## デプロイ手順

### ステップ 1: デプロイの実行

リポジトリルートから対話型スクリプトを実行する。

```bash
bash infra/deploy.sh
```

スクリプトが以下を対話形式で確認する。

1. サブスクリプションの選択（一覧から番号で選択）
2. リソースグループの選択（一覧から番号で選択）
3. AI Foundry アカウントの選択（自動検出、複数の場合は番号で選択）
4. プロキシ API キーの入力（Cline から接続する際に使うキー。8文字以上）
5. デプロイ環境の選択（`dev` または `prod`）
6. 設定内容の確認

スクリプトが自動で以下を実行する。

- **フェーズ1**: ARM テンプレート（`arm/main.json`）をデプロイ（ACR・CA 環境・UAMI・監視）
- **フェーズ2**: Docker イメージをビルドして ACR へプッシュ
- **フェーズ3**: ARM テンプレート（`arm/app.json`）をデプロイ（Container App）

完了すると以下が表示される。

```
  API エンドポイント : https://ca-cline-api-xxxxxxxx.xxx.japaneast.azurecontainerapps.io
  Container App 名   : ca-cline-api-xxxxxxxx

  【Cline の設定】
  API Provider   : OpenAI Compatible
  Base URL       : https://ca-cline-api-xxxxxxxx.xxx.japaneast.azurecontainerapps.io/v1
  API Key        : (デプロイ時に設定したプロキシ API キー)
  Model          : gpt-4.1-mini
```

---

### ステップ 2: Cline の設定

VS Code の Cline 拡張機能を以下のように設定する。

| 設定項目 | 値 |
|---|---|
| API Provider | `OpenAI Compatible` |
| Base URL | `https://<Container App の FQDN>/v1` |
| API Key | デプロイ時に入力したプロキシ API キー |
| Model | `gpt-4.1-mini` |

---

## 動作確認

以下の curl コマンドで API が正常に動作していることを確認する。

### モデル一覧の取得

```bash
API_KEY="<プロキシ API キー>"
FQDN="<Container App の FQDN>"

curl -s \
  -H "Authorization: Bearer ${API_KEY}" \
  https://${FQDN}/v1/models | jq .
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
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"Hello!"}]}' \
  https://${FQDN}/v1/chat/completions | jq .choices[0].message.content
```

---

## Bicep ファイルを変更した場合

`infra/*.bicep` または `infra/modules/*.bicep` を変更した場合は、ARM JSON を再生成してコミットする。  
デプロイには ARM JSON を使うため、この手順を省略すると変更が反映されない。

```bash
# ARM JSON を再生成（Azure CLI + Bicep CLI が必要）
bash infra/build.sh

# 生成された ARM JSON をコミット
git add infra/arm/
git commit -m "build: update ARM templates"
```

---

## リソースの削除

環境を削除するには以下を実行する。

```bash
bash infra/destroy.sh
```

スクリプトが `project=cline-ready-api-with-az` タグ付きリソースの一覧を表示し、確認後に削除する。  
AI Foundry などのタグなしリソースは削除されない。

---

## トラブルシューティング

### Container App が起動しない

Container App のシステムログを確認する。

```bash
az containerapp logs show \
  --name <Container App 名> \
  --resource-group <RG名> \
  --type system \
  --tail 30
```

コンテナのアプリケーションログを確認する。

```bash
az containerapp logs show \
  --name <Container App 名> \
  --resource-group <RG名> \
  --tail 50
```

リビジョンの状態を確認する。

```bash
az containerapp revision list \
  --name <Container App 名> \
  --resource-group <RG名> \
  --query "[].{Name:name, Active:properties.active, State:properties.runningState}" \
  --output table
```

### 401 Unauthorized が返る

Container App に設定されたシークレットを確認する。

```bash
az containerapp secret list \
  --name <Container App 名> \
  --resource-group <RG名> \
  --output table
```

`api-key-value` が存在しない場合は `deploy.sh` を再実行するか、以下で手動設定する。

```bash
az containerapp secret set \
  --name <Container App 名> \
  --resource-group <RG名> \
  --secrets api-key-value=<キーの値>
```

### ACR からイメージをプルできない

UAMI に `AcrPull` ロールが付与されているか確認する。

```bash
az role assignment list \
  --scope $(az acr show --name <ACR名> --query id --output tsv) \
  --output table
```

ロールが存在しない場合、または付与直後の場合は 2〜5 分待ってから Container App を再起動する。

```bash
az containerapp revision restart \
  --name <Container App 名> \
  --resource-group <RG名> \
  --revision <リビジョン名>
```
