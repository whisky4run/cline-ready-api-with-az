# Docker + ACR 回避デプロイ方式

企業プロキシ環境で Azure Container Registry（ACR）にアクセスできない場合の代替デプロイ方式です。

## 📋 概要

標準的なローカル Docker → ACR のデプロイフローは、企業プロキシによる SSL/TLS傍受でブロックされます。以下の代替方式を用意しました：

| 方式 | 利点 | 難点 | 推奨度 |
|------|------|------|--------|
| **GitHub Actions** | プロキシの影響なし。クラウド上で実行 | OIDC認証設定が必要 | ⭐⭐⭐ |
| **Azure Cloud Shell** | プロキシの影響なし。セットアップ不要 | 対話型コマンド | ⭐⭐ |
| **Docker Build Context URL** | ローカルで実行可能 | プロキシ設定の工夫が必要 | ⭐ |

---

## 🚀 方式1：GitHub Actions（最推奨）

### セットアップ

#### 1️⃣ Azure OIDC 認証を構成

```bash
# Azure Portal → Cloud Shell を起動（Bash）

# リポジトリをクローン
cd ~
git clone --branch one-api https://github.com/whisky4run/cline-ready-api-with-az.git
cd cline-ready-api-with-az
```

#### 2️⃣ GitHub Repository Secrets を設定

GitHub → Settings → Secrets and variables → Actions → New repository secret

以下を追加：

```
AZURE_CLIENT_ID         = <OIDC App ID>
AZURE_TENANT_ID         = <Tenant ID>
AZURE_SUBSCRIPTION_ID   = <Subscription ID>
```

#### 3️⃣ GitHub Actions ワークフローを実行

```bash
# リポジトリをプッシュ
git add .github/workflows/deploy-acr.yml
git commit -m "ci: add GitHub Actions workflow for ACR build"
git push

# GitHub → Actions → "Build & Push to ACR" → Run workflow
# Input:
#   - ACR Name: acrclineapiuiankni2
#   - Image tag: latest
```

### メリット
- ✅ 企業プロキシの影響を受けない（GitHub のサーバーから実行）
- ✅ 完全に自動化可能
- ✅ CI/CD パイプラインに統合可能

---

## 🌐 方式2：Azure Cloud Shell

### 実行手順

```bash
# Azure Portal → Cloud Shell を起動（Bash）

# リポジトリをクローン
cd ~
git clone https://github.com/whisky4run/cline-ready-api-with-az.git
cd cline-ready-api-with-az

# ビルド&プッシュ（ローカルプロキシの影響なし）
# ⚠️ 重要：SOURCE_LOCATION として . を指定（リポジトリルートを指定）
az acr build \
  --registry acrclineapiuiankni2 \
  --image cline-api:latest \
  --file src/ClineApiWithAz/Dockerfile \
  .

# 完了確認
az acr repository show --name acrclineapiuiankni2 --image cline-api:latest
```

### メリット
- ✅ セットアップ不要（すぐ実行可能）
- ✅ プロキシの影響を受けない
- ✅ Azure リソースへの認証が自動

### デメリット
- ❌ 手動実行
- ❌ スクリプトの自動化が複雑

---

## 🔧 方式3：デプロイスクリプトの修正版

ローカルマシンで実行し、プロキシ設定を一時的に無効化（⚠️ 本番環境非推奨）

```bash
#!/bin/bash
# infra/deploy-no-docker.sh
# ⚠️ Cloud Shell または GitHub Actions で実行してください

ACR_NAME="acrclineapiuiankni2"
RESOURCE_GROUP="rg-cline-api"
LOCATION="japaneast"

# フェーズ1: インフラ構築
echo "[INFO] フェーズ1: インフラ構築中..."
az deployment group create \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file infra/arm/main.json \
  --parameters env=dev location="${LOCATION}" \
    modelName=gpt-4.1-mini modelVersion=2025-04-14 \
  --output none

echo "[OK] フェーズ1 完了"
echo ""

# フェーズ2: Azure 上でのビルド&プッシュ
echo "[INFO] フェーズ2: ACR でビルド中..."
echo "  ⏳ 初回は 5-10 分かかります..."

# ⚠️ 重要：SOURCE_LOCATION として . を指定（リポジトリルートから実行）
az acr build \
  --registry "${ACR_NAME}" \
  --image cline-api:latest \
  --file src/ClineApiWithAz/Dockerfile \
  . \
  --timeout 900  # 15分

if [ $? -ne 0 ]; then
  echo "[ERROR] ビルドが失敗しました"
  exit 1
fi

echo "[OK] フェーズ2 完了"
echo ""

# フェーズ3: Container App デプロイ
echo "[INFO] フェーズ3: Container App デプロイ中..."
# 以下のコマンドで deploy.sh の残りを実行（または手動で実行）
# bash infra/deploy.sh
```

---

## 📊 比較表

| 項目 | GitHub Actions | Cloud Shell | ローカル修正版 |
|------|---|---|---|
| プロキシ影響 | なし | なし | あり（工夫必要） |
| セットアップ | 必要 | 不要 | 不要 |
| 自動化可能 | ○ | △ | ○ |
| 推奨環境 | 本番 CI/CD | 検証・テスト | 非推奨 |

---

## ✅ 推奨フロー

### 小規模・テスト環境
```
1. Cloud Shell で az acr build 実行
2. Container App デプロイ成功確認
3. 本デプロイ前に GitHub Actions を構成
```

### 本番・自動化環境
```
1. GitHub OIDC 認証を構成
2. GitHub Actions ワークフローを実行
3. 定期ビルド・デプロイを自動化
```

---

## 🔐 セキュリティ注意点

⚠️ **ローカル環境でのプロキシ無効化は非推奨**
- SSL/TLS検証を無効にするリスク
- 中間者攻撃（MITM）の可能性
- 企業セキュリティポリシー違反の可能性

✅ **推奨**
- GitHub Actions または Cloud Shell を使用
- 企業IT部門にホワイトリスト登録を依頼
- OIDC 認証で安全なアクセス

---

## 🆘 トラブルシューティング

### GitHub Actions で OIDC エラーが出る場合

```bash
# OIDC の認証情報を確認
az ad app show --id <CLIENT_ID> \
  --query "displayName, appId" --output table

# OIDC フェデレーション設定を確認
az identity federated-credentials list \
  --resource-group <RG> \
  --identity-name <IDENTITY_NAME>
```

### `az acr build` がタイムアウトする場合

Cloud Shell で実行（ローカルネットワーク遅延を回避）：

```bash
# Cloud Shell → 同じコマンドを実行
az acr build --registry acrclineapiuiankni2 \
  --image cline-api:latest \
  --file src/ClineApiWithAz/Dockerfile \
  . \
  --timeout 900  # 15分に延長
```

---

## 📚 参考リンク

- [Azure Container Registry - az acr build](https://docs.microsoft.com/en-us/cli/azure/acr?view=azure-cli-latest#az-acr-build)
- [GitHub Actions - Azure Login](https://github.com/Azure/login)
- [Azure Cloud Shell - はじめに](https://docs.microsoft.com/en-us/azure/cloud-shell/overview)
