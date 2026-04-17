# 企業プロキシ環境対応：Cloud Shell 統合デプロイガイド

企業プロキシで Docker + ACR がブロックされている環境向けの**実行可能なデプロイ手順**です。

## 📋 全体フロー

```
ローカルマシン              Cloud Shell          Azure
┌─────────────┐           ┌──────────┐        ┌────────────┐
│ フェーズ1   │           │ フェーズ2 │        │  Azure     │
│ インフラ    │──[出力]──→│ ビルド   │─[ACR]→│ Container  │
│ 構築        │           │ &デプロイ │        │ App        │
└─────────────┘           └──────────┘        └────────────┘
  ↓                         ↓
  bash                      bash
  deploy-phase1.sh          deploy-cloud-shell.sh
```

---

## ✅ 前提条件

| 項目 | ローカル | Cloud Shell |
|------|---------|-----------|
| **Docker** | ❌ 不要 | ✅ (Azure が提供) |
| **Azure CLI** | ✅ 必須 | ✅ (組み込み) |
| **プロキシ影響** | ❌ ブロック | ✅ なし |

---

## 🚀 ステップバイステップ実行手順

### ステップ1: ローカルで前準備（2分）

```bash
# リポジトリをクローン（未実施の場合）
git clone --branch one-api https://github.com/whisky4run/cline-ready-api-with-az.git
cd cline-ready-api-with-az
```

**重要:** ⚠️ `build.sh` は実行不要です
- プロキシの影響を受けるため、**スキップしてください**
- 既に `infra/arm/main.json` と `infra/arm/app.json` が存在するため、ARM テンプレートをそのまま使用

**確認:** 以下のファイルが存在することを確認
```bash
ls -la infra/arm/main.json infra/arm/app.json
```

---

### ステップ2: ローカルでフェーズ1 実行（10分）

```bash
# インフラ構築のみ（Docker 不要、Bicep コンパイル不要）
bash infra/deploy-phase1.sh
```

**重要:** このスクリプトは既存の ARM テンプレートを使用します
- Bicep コンパイルはスキップされています
- プロキシの影響を受けません

**対話型入力:**
1. サブスクリプションを選択
2. リソースグループを選択
3. AI モデルを指定
4. デプロイ確認

**出力画面例:**
```
╔══════════════════════════════════════════════════════════╗
║           フェーズ1 完了！                               ║
╚══════════════════════════════════════════════════════════╝

  💾 以下の情報を控えてください（フェーズ2で使用）:

    SUBSCRIPTION_ID=2980c139-a701-4a39-89af-83495557b56b
    RESOURCE_GROUP=rg-cline-api
    ACR_NAME=acrclineapiuiankni2
    AI_ENDPOINT=https://jpe-cline-ai.openai.azure.com/
    AI_API_KEY=d8f6c9e2a1b5...
    AI_MODEL_NAME=gpt-4.1-mini
```

⚠️ **これらの値を控えておいてください！**

---

### ステップ3: Cloud Shell でフェーズ2＆3 実行（15分）

#### 3-1. Cloud Shell を起動

```bash
# Azure Portal の右上 > Cloud Shell アイコン をクリック
# または: https://shell.azure.com
```

#### 3-2. リポジトリをクローン

```bash
cd ~
git clone --branch one-api https://github.com/whisky4run/cline-ready-api-with-az.git
cd cline-ready-api-with-az
```

#### 3-3. デプロイスクリプト実行

```bash
bash infra/deploy-cloud-shell.sh
```

**対話型入力 - ステップ2 で控えた情報を入力:**

```
サブスクリプション ID を入力してください: 
2980c139-a701-4a39-89af-83495557b56b

リソースグループ名を入力してください:
rg-cline-api

ACR 名を入力してください:
acrclineapiuiankni2

環境を選択してください (dev/prod) [デフォルト: dev]:
dev

AI Foundry エンドポイント (https://...):
https://jpe-cline-ai.openai.azure.com/

AI Foundry API キー:
d8f6c9e2a1b5...

プロキシ API キー:
sk-myteam-2024

AI モデル名 (例: gpt-4.1-mini):
gpt-4.1-mini
```

**実行ログ例:**
```
[INFO]  Azure 上で Docker イメージをビルド中...
  ⏳ 初回は 5-10 分かかります。お待ちください...

  Sending build context to ACR...
  Queued a build for sha
  
  [OK] イメージビルド & ACR プッシュ完了

[INFO] ARM テンプレートをデプロイ中...

╔══════════════════════════════════════════════════════════╗
║              デプロイ完了！                              ║
╚══════════════════════════════════════════════════════════╝

  API エンドポイント : https://ca-cline-api-xxxx.japaneast.containerapp.io
  Container App 名   : ca-cline-api-xxxx
```

**保存:** **API エンドポイント** をコピー

---

## 📊 実行時間の目安

| フェーズ | 場所 | 作業 | 時間 |
|---------|------|------|------|
| **1** | ローカル | インフラ構築 | 5分 |
| **2** | Cloud Shell | イメージビルド | 5-10分 |
| **3** | Cloud Shell | Container App デプロイ | 2-3分 |
| **合計** | | | **15-20分** |

---

## 🔧 実行ファイル一覧

| ファイル | 説明 | 実行環境 |
|---------|------|---------|
| `infra/build.sh` | Bicep → ARM JSON | ローカル |
| `infra/deploy-phase1.sh` | フェーズ1（インフラ） | ローカル |
| `infra/deploy-cloud-shell.sh` | フェーズ2&3（ビルド+デプロイ） | Cloud Shell |
| `infra/deploy.sh` | 従来の統合スクリプト（Docker 環境向け） | ローカル |

---

## 📝 トラブルシューティング

### Q: `deploy-phase1.sh` でリソースグループが見つからない

```bash
# リソースグループを先に作成
az group create \
  --name rg-cline-api \
  --location japaneast
```

### Q: Cloud Shell でリポジトリをクローンできない

```bash
# パスを確認（Cloud Shell は 5GB 制限）
df -h /home

# キャッシュをクリア
rm -rf ~/.cache/*
```

### Q: `az acr build` がタイムアウト

Cloud Shell の方が安定しています。既に Cloud Shell で実行している場合は再度実行してください：

```bash
az acr build \
  --registry acrclineapiuiankni2 \
  --image cline-api:latest \
  --file src/ClineApiWithAz/Dockerfile \
  . \
  --timeout 900
```

### Q: Container App が起動しない

```bash
# ログを確認
az containerapp logs show \
  --resource-group rg-cline-api \
  --name ca-cline-api-xxxx \
  --type system \
  --tail 50
```

---

## 🎯 Cline での使用設定

デプロイ完了後、Cline に以下を設定：

```
プロバイダー: OpenAI Compatible
Base URL:    https://ca-cline-api-xxxx.japaneast.containerapp.io/v1
API Key:     sk-myteam-2024 (ステップ3で設定したもの)
モデル:       gpt-4.1-mini
```

---

## 📚 ファイル構成

```
infra/
├── build.sh                    # Bicep → ARM JSON ビルド
├── deploy.sh                   # 従来の統合スクリプト（Docker 環境向け）
├── deploy-phase1.sh           # ✅ フェーズ1: インフラ構築（ローカル実行）
├── deploy-cloud-shell.sh      # ✅ フェーズ2&3: ビルド+デプロイ（Cloud Shell 実行）
├── main.bicep                 # インフラコード
├── app.bicep                  # Container App コード
├── arm/
│   ├── main.json             # 生成済み ARM テンプレート
│   └── app.json              # 生成済み ARM テンプレート
└── modules/
    └── ...
```

---

## ✅ 検証チェックリスト

デプロイ完了後の確認項目：

```bash
# 1. リソースグループが作成されているか
az group list --query "[?name=='rg-cline-api']"

# 2. ACR にイメージが存在するか
az acr repository show --name acrclineapiuiankni2 --image cline-api:latest

# 3. Container App が動作しているか
az containerapp show --resource-group rg-cline-api --name ca-cline-api-xxxx

# 4. API が応答するか
curl https://ca-cline-api-xxxx.japaneast.containerapp.io/v1/models \
  -H "Authorization: Bearer sk-myteam-2024"
```

---

## 🔐 セキュリティ注記

| 項目 | 対応 |
|------|------|
| API キー | 環境変数 + Azure Container App secrets で保管 |
| ネットワーク | Public endpoint（必要に応じて IP 制限可能） |
| プロキシ対応 | Cloud Shell 使用で企業プロキシ回避 |
| SSL/TLS | 自動的に Azure マネージド証明書 |

---

## 🆘 追加サポート

問題が解決しない場合：

1. **Cloud Shell のログを確認**
   ```bash
   # デプロイメント履歴
   az deployment group list --resource-group rg-cline-api --query "[].name"
   
   # 詳細ログ
   az deployment group show \
     --resource-group rg-cline-api \
     --name <deployment-name> \
     --query properties.outputs
   ```

2. **Container App リソース確認**
   ```bash
   az containerapp revision list \
     --resource-group rg-cline-api \
     --name ca-cline-api-xxxx \
     --output table
   ```

3. **Azure Portal で確認**
   - Resource Group → Container App → ログストリーム
