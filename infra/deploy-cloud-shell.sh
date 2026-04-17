#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# cline-ready-api-with-az — Cloud Shell 統合デプロイ
#
# 企業プロキシ環境で Docker + ACR が利用できない場合のデプロイスクリプト
#
# 実行環境: Azure Cloud Shell (Bash)
# 前提条件:
#   - Azure Cloud Shell でこのスクリプトを実行
#   - リポジトリが既にクローン済み
#   - フェーズ1（インフラ構築）が既に完了している
#
# 実行手順:
#   1. Azure Portal でリソースグループを作成
#   2. ローカルマシンで deploy-phase1.sh を実行（インフラ構築）
#   3. Cloud Shell でこのスクリプト（フェーズ2&3）を実行
#
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─── 色付きメッセージ ─────────────────────────────────────────
info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  Cloud Shell 統合デプロイ（フェーズ2 & 3）               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ─── 入力値の確認 ──────────────────────────────────────────────
info "デプロイ情報を入力してください..."
echo ""

read -r -p "サブスクリプション ID を入力してください: " SUBSCRIPTION_ID
read -r -p "リソースグループ名を入力してください (例: rg-cline-api): " RESOURCE_GROUP
read -r -p "ACR 名を入力してください (例: acrclineapiuiankni2): " ACR_NAME
read -r -p "環境を選択してください (dev/prod) [デフォルト: dev]: " ENV_INPUT
ENV="${ENV_INPUT:-dev}"

# AI Foundry 情報（フェーズ1でデプロイ済みの出力から取得）
info ""
info "フェーズ1 の出力から取得した情報を入力してください..."
echo ""
read -r -p "AI Foundry エンドポイント (https://...): " AI_ENDPOINT
read -r -s -p "AI Foundry API キー: " AI_API_KEY
echo ""
read -r -s -p "プロキシ API キー: " PROXY_API_KEY
echo ""
read -r -p "AI モデル名 (例: gpt-4.1-mini): " AI_MODEL_NAME

# サブスクリプション設定
az account set --subscription "${SUBSCRIPTION_ID}"
success "サブスクリプション設定完了"

echo ""
echo "──────────────────────────────────────────────────────────"
echo "  デプロイ設定の確認"
echo "──────────────────────────────────────────────────────────"
echo "  サブスクリプション   : ${SUBSCRIPTION_ID}"
echo "  リソースグループ   : ${RESOURCE_GROUP}"
echo "  ACR 名              : ${ACR_NAME}"
echo "  環境                : ${ENV}"
echo "  AI モデル           : ${AI_MODEL_NAME}"
echo "──────────────────────────────────────────────────────────"
echo ""

read -r -p "上記の設定で進行しますか？ (y/N): " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  info "キャンセルしました。"
  exit 0
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# フェーズ2: コンテナイメージのビルドとプッシュ
# ═══════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  フェーズ2: コンテナイメージビルド & ACR プッシュ        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

info "Azure 上で Docker イメージをビルド中..."
echo "  ⏳ 初回は 5-10 分かかります。お待ちください..."
echo ""

# Cloud Shell での az acr build は、ローカルプロキシの影響を受けない
az acr build \
  --registry "${ACR_NAME}" \
  --image cline-api:latest \
  --file src/ClineApiWithAz/Dockerfile \
  . \
  --timeout 900

if [ $? -ne 0 ]; then
  error "ビルドが失敗しました。ログを確認してください。"
  exit 1
fi

success "イメージビルド & ACR プッシュ完了"
echo ""

# ─── 完了確認 ──────────────────────────────────────────────────
info "イメージが ACR にプッシュされたことを確認中..."
IMAGE_INFO=$(az acr repository show \
  --name "${ACR_NAME}" \
  --repository cline-api \
  --query "{repository: name, tags: tags}" \
  --output json)

success "イメージ確認完了："
echo "${IMAGE_INFO}" | jq '.'
echo ""

# ═══════════════════════════════════════════════════════════════
# フェーズ3: Container App デプロイ
# ═══════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  フェーズ3: Container App デプロイ                       ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

ARM_APP="${SCRIPT_DIR}/arm/app.json"

if [[ ! -f "${ARM_APP}" ]]; then
  error "ARM テンプレートが見つかりません: ${ARM_APP}"
  error "ローカルマシンで deploy-phase1.sh を実行してください。"
  exit 1
fi

PHASE3_DEPLOYMENT_NAME="cline-api-phase3-$(date +%Y%m%d%H%M%S)"

info "ARM テンプレートをデプロイ中..."
echo ""

if ! az deployment group create \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${PHASE3_DEPLOYMENT_NAME}" \
  --template-file "${ARM_APP}" \
  --parameters \
    env="${ENV}" \
    azureAiEndpoint="${AI_ENDPOINT}" \
    azureAiApiKey="${AI_API_KEY}" \
    apiKeyValue="${PROXY_API_KEY}" \
    modelName="${AI_MODEL_NAME}" \
  --output none; then

  error "フェーズ3 デプロイが失敗しました。"
  exit 1
fi

success "フェーズ3 デプロイ完了"
echo ""

# ─── デプロイ結果を表示 ───────────────────────────────────────
API_ENDPOINT=$(az deployment group show \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${PHASE3_DEPLOYMENT_NAME}" \
  --query "properties.outputs.apiEndpoint.value" \
  --output tsv 2>/dev/null || echo "(取得失敗)")

CA_NAME=$(az deployment group show \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${PHASE3_DEPLOYMENT_NAME}" \
  --query "properties.outputs.containerAppName.value" \
  --output tsv 2>/dev/null || echo "(取得失敗)")

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              デプロイ完了！                              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  API エンドポイント : ${API_ENDPOINT}"
echo "  Container App 名   : ${CA_NAME}"
echo ""
echo "──────────────────────────────────────────────────────────"
echo "  【Cline の設定】"
echo "──────────────────────────────────────────────────────────"
echo "  API Provider   : OpenAI Compatible"
echo "  Base URL       : ${API_ENDPOINT}/v1"
echo "  API Key        : (デプロイ時に設定したプロキシ API キー)"
echo "  Model          : ${AI_MODEL_NAME}"
echo "──────────────────────────────────────────────────────────"
echo ""
