#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# cline-ready-api-with-az — 対話型デプロイスクリプト（2フェーズ）
#
# 前提: 既存のリソースグループに AI Foundry (Cognitive Services) が
#       作成されていること。本スクリプトはそのリソースグループに
#       ACR / Cosmos / Key Vault / Container Apps を追加します。
#
# フェーズ1: インフラ構築（main.bicep）
#   - Monitoring, Key Vault, ACR, Cosmos DB, Container Apps 環境
# 自動実行される作業:
#   - AI Foundry エンドポイント/API キーの自動取得と Key Vault 登録
#   - Cosmos 接続文字列の自動取得と Key Vault 登録
#   - Docker イメージのビルドと ACR へのプッシュ
# フェーズ2: アプリデプロイ（app.bicep）
#   - Container App 本体 + マネージド ID へのロール割り当て
#
# 使用方法: bash infra/deploy.sh
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─── 色付きメッセージ ─────────────────────────────────────────
info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# ═══════════════════════════════════════════════════════════════
# 前提条件チェック
# ═══════════════════════════════════════════════════════════════
info "前提条件をチェックしています..."

# Azure CLI
if ! command -v az &>/dev/null; then
  error "Azure CLI が見つかりません。"
  error "  インストール: https://docs.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi
success "Azure CLI: $(az version --query '\"azure-cli\"' --output tsv 2>/dev/null || echo 'インストール済み')"

# Docker CLI
if ! command -v docker &>/dev/null; then
  error "Docker CLI が見つかりません。"
  error "  インストール: https://docs.docker.com/get-docker/"
  exit 1
fi

# Docker Desktop 起動確認
if ! docker info &>/dev/null; then
  error "Docker デーモンに接続できません。Docker Desktop を起動してください。"
  exit 1
fi
success "Docker: 起動中"

# Azure ログイン確認
if ! az account show &>/dev/null; then
  info "Azure にログインしていません。ログインします..."
  az login
fi
success "Azure ログイン: $(az account show --query user.name --output tsv)"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     cline-ready-api-with-az  デプロイセットアップ        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ═══════════════════════════════════════════════════════════════
# 対話型入力
# ═══════════════════════════════════════════════════════════════

# ─── サブスクリプション選択 ───────────────────────────────────
info "利用可能なサブスクリプション一覧:"
echo ""
az account list --query "[].{Id:id, Name:name, State:state}" --output table
echo ""

while true; do
  read -r -p "サブスクリプション名または ID を入力してください: " SUBSCRIPTION_INPUT
  if [[ -z "${SUBSCRIPTION_INPUT}" ]]; then
    warn "入力が空です。再入力してください。"
    continue
  fi

  if az account set --subscription "${SUBSCRIPTION_INPUT}" 2>/dev/null; then
    SUBSCRIPTION_ID=$(az account show --query id --output tsv)
    SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
    success "サブスクリプション「${SUBSCRIPTION_NAME}」（${SUBSCRIPTION_ID}）を選択しました。"
    break
  else
    error "サブスクリプション「${SUBSCRIPTION_INPUT}」が見つかりません。再入力してください。"
  fi
done

echo ""

# ─── リソースグループ選択（既存のみ） ────────────────────────
info "利用可能なリソースグループ一覧:"
echo ""

RG_LIST=()
while IFS=$'\t' read -r rg_name rg_loc; do
  RG_LIST+=("${rg_name}"$'\t'"${rg_loc}")
done < <(az group list --subscription "${SUBSCRIPTION_ID}" \
  --query "sort_by([], &name)[].[name, location]" --output tsv)

if [[ ${#RG_LIST[@]} -eq 0 ]]; then
  error "リソースグループが見つかりません。"
  error "  先に AI Foundry を含むリソースグループを Azure Portal で作成してください。"
  exit 1
fi

for i in "${!RG_LIST[@]}"; do
  IFS=$'\t' read -r rg_name rg_loc <<< "${RG_LIST[$i]}"
  printf "  %2d) %-45s %s\n" "$((i+1))" "${rg_name}" "${rg_loc}"
done
echo ""

while true; do
  read -r -p "リソースグループ番号を入力してください (1-${#RG_LIST[@]}): " RG_IDX
  if [[ "${RG_IDX}" =~ ^[0-9]+$ ]] && (( RG_IDX >= 1 && RG_IDX <= ${#RG_LIST[@]} )); then
    IFS=$'\t' read -r RESOURCE_GROUP LOCATION <<< "${RG_LIST[$((RG_IDX-1))]}"
    success "リソースグループ: ${RESOURCE_GROUP} (${LOCATION})"
    break
  else
    warn "1〜${#RG_LIST[@]} の範囲で番号を入力してください。"
  fi
done

echo ""

# ─── AI Foundry アカウント検出 ───────────────────────────────
info "リソースグループ内の AI Foundry (Cognitive Services) を検索中..."

AI_ACCOUNTS=()
while IFS=$'\t' read -r ai_name ai_kind ai_endpoint; do
  [[ -z "${ai_name}" ]] && continue
  AI_ACCOUNTS+=("${ai_name}"$'\t'"${ai_kind}"$'\t'"${ai_endpoint}")
done < <(az cognitiveservices account list \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "[].[name, kind, properties.endpoint]" \
  --output tsv 2>/dev/null)

if [[ ${#AI_ACCOUNTS[@]} -eq 0 ]]; then
  error "リソースグループ「${RESOURCE_GROUP}」に Cognitive Services アカウントが見つかりません。"
  error "  先に Azure Portal で AI Foundry (Cognitive Services) アカウントを作成してください。"
  exit 1
fi

if [[ ${#AI_ACCOUNTS[@]} -eq 1 ]]; then
  IFS=$'\t' read -r AI_NAME AI_KIND AI_ENDPOINT <<< "${AI_ACCOUNTS[0]}"
  success "AI Foundry アカウント: ${AI_NAME} (${AI_KIND})"
else
  echo ""
  info "複数の Cognitive Services アカウントが見つかりました:"
  for i in "${!AI_ACCOUNTS[@]}"; do
    IFS=$'\t' read -r n k e <<< "${AI_ACCOUNTS[$i]}"
    printf "  %2d) %-40s %s\n" "$((i+1))" "${n}" "${k}"
  done
  echo ""
  while true; do
    read -r -p "アカウント番号を入力してください (1-${#AI_ACCOUNTS[@]}): " AI_IDX
    if [[ "${AI_IDX}" =~ ^[0-9]+$ ]] && (( AI_IDX >= 1 && AI_IDX <= ${#AI_ACCOUNTS[@]} )); then
      IFS=$'\t' read -r AI_NAME AI_KIND AI_ENDPOINT <<< "${AI_ACCOUNTS[$((AI_IDX-1))]}"
      success "AI Foundry アカウント: ${AI_NAME} (${AI_KIND})"
      break
    else
      warn "1〜${#AI_ACCOUNTS[@]} の範囲で番号を入力してください。"
    fi
  done
fi

info "API キーを取得中..."
AI_API_KEY=$(az cognitiveservices account keys list \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AI_NAME}" \
  --query key1 \
  --output tsv)

if [[ -z "${AI_API_KEY}" ]]; then
  error "API キーの取得に失敗しました。アカウントの権限を確認してください。"
  exit 1
fi
success "エンドポイント: ${AI_ENDPOINT}"
success "API キー: (${#AI_API_KEY} 文字を取得)"

echo ""

# ─── 環境選択 ─────────────────────────────────────────────────
while true; do
  read -r -p "デプロイ環境を選択してください (dev / prod) [デフォルト: dev]: " ENV_INPUT
  ENV="${ENV_INPUT:-dev}"
  if [[ "${ENV}" == "dev" || "${ENV}" == "prod" ]]; then
    success "環境: ${ENV}"
    break
  else
    warn "「dev」または「prod」を入力してください。"
  fi
done

echo ""

# ─── 確認 ─────────────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────"
echo "  デプロイ設定の確認"
echo "──────────────────────────────────────────────────────────"
echo "  サブスクリプション : ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
echo "  リソースグループ   : ${RESOURCE_GROUP}"
echo "  リージョン         : ${LOCATION}"
echo "  環境               : ${ENV}"
echo "  AI Foundry 名       : ${AI_NAME} (${AI_KIND})"
echo "  AI Foundry URL     : ${AI_ENDPOINT}"
echo "  AI Foundry Key     : (${#AI_API_KEY} 文字)"
echo "──────────────────────────────────────────────────────────"
echo ""

read -r -p "上記の設定でデプロイを開始しますか？ (y/N): " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  info "デプロイをキャンセルしました。"
  exit 0
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# フェーズ1: インフラ構築（main.bicep）
# ═══════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           フェーズ1: インフラ構築                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

PHASE1_DEPLOYMENT_NAME="cline-api-phase1-$(date +%Y%m%d%H%M%S)"
PARAM_FILE="${SCRIPT_DIR}/parameters/${ENV}.bicepparam"
MAIN_BICEP="${SCRIPT_DIR}/main.bicep"

info "Bicep デプロイを開始します（デプロイ名: ${PHASE1_DEPLOYMENT_NAME}）..."
echo ""

az deployment group create \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${PHASE1_DEPLOYMENT_NAME}" \
  --template-file "${MAIN_BICEP}" \
  --parameters "${PARAM_FILE}" location="${LOCATION}" \
  --output none

success "フェーズ1 デプロイが完了しました。"
echo ""

# ─── フェーズ1の出力を取得 ────────────────────────────────────
get_output() {
  az deployment group show \
    --subscription "${SUBSCRIPTION_ID}" \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${PHASE1_DEPLOYMENT_NAME}" \
    --query "properties.outputs.$1.value" \
    --output tsv 2>/dev/null || echo ""
}

KEY_VAULT_URI=$(get_output keyVaultUri)
KEY_VAULT_NAME=$(get_output keyVaultName)
ACR_LOGIN_SERVER=$(get_output acrLoginServer)
ACR_NAME=$(get_output acrName)
COSMOS_ACCOUNT=$(get_output cosmosAccountName)

echo "──────────────────────────────────────────────────────────"
echo "  フェーズ1 の出力"
echo "──────────────────────────────────────────────────────────"
echo "  Key Vault 名        : ${KEY_VAULT_NAME}"
echo "  Key Vault URI       : ${KEY_VAULT_URI}"
echo "  ACR 名              : ${ACR_NAME}"
echo "  ACR ログインサーバー: ${ACR_LOGIN_SERVER}"
echo "  Cosmos DB アカウント: ${COSMOS_ACCOUNT}"
echo "──────────────────────────────────────────────────────────"
echo ""

# ═══════════════════════════════════════════════════════════════
# Key Vault シークレット登録
# ═══════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       Key Vault シークレットの自動登録                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# 自分に一時的に Key Vault Secrets Officer ロールを付与（シークレット書き込みのため）
CURRENT_USER_OID=$(az ad signed-in-user show --query id --output tsv)
KV_ID=$(az keyvault show --name "${KEY_VAULT_NAME}" --query id --output tsv)

info "自分に一時的な Key Vault Secrets Officer ロールを付与します..."
az role assignment create \
  --assignee-object-id "${CURRENT_USER_OID}" \
  --assignee-principal-type User \
  --role "Key Vault Secrets Officer" \
  --scope "${KV_ID}" \
  --output none 2>/dev/null || true

info "ロール付与の反映を待機しています（30秒）..."
sleep 30

# AzureAI--Endpoint
info "シークレット AzureAI--Endpoint を登録中..."
az keyvault secret set \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "AzureAI--Endpoint" \
  --value "${AI_ENDPOINT}" \
  --output none
success "  AzureAI--Endpoint 登録完了"

# AzureAI--ApiKey
info "シークレット AzureAI--ApiKey を登録中..."
az keyvault secret set \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "AzureAI--ApiKey" \
  --value "${AI_API_KEY}" \
  --output none
success "  AzureAI--ApiKey 登録完了"

# CosmosDb--ConnectionString（自動取得）
info "Cosmos DB 接続文字列を取得中..."
COSMOS_CONN=$(az cosmosdb keys list \
  --name "${COSMOS_ACCOUNT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --type connection-strings \
  --query "connectionStrings[0].connectionString" \
  --output tsv)

info "シークレット CosmosDb--ConnectionString を登録中..."
az keyvault secret set \
  --vault-name "${KEY_VAULT_NAME}" \
  --name "CosmosDb--ConnectionString" \
  --value "${COSMOS_CONN}" \
  --output none
success "  CosmosDb--ConnectionString 登録完了"

echo ""

# ═══════════════════════════════════════════════════════════════
# コンテナイメージのビルドとプッシュ
# ═══════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       コンテナイメージのビルドとプッシュ                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

info "ACR にログイン中..."
az acr login --name "${ACR_NAME}" --output none
success "ACR ログイン完了"

IMAGE_TAG="${ACR_LOGIN_SERVER}/cline-api:latest"

info "Docker イメージをビルド中: ${IMAGE_TAG}"
docker build \
  -t "${IMAGE_TAG}" \
  -f "${REPO_ROOT}/src/ClineApiWithAz/Dockerfile" \
  "${REPO_ROOT}"
success "イメージビルド完了"

info "Docker イメージを ACR にプッシュ中..."
docker push "${IMAGE_TAG}"
success "イメージプッシュ完了"

echo ""

# ═══════════════════════════════════════════════════════════════
# フェーズ2: Container App + ロール割り当て（app.bicep）
# ═══════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           フェーズ2: Container App デプロイ              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

PHASE2_DEPLOYMENT_NAME="cline-api-phase2-$(date +%Y%m%d%H%M%S)"
APP_BICEP="${SCRIPT_DIR}/app.bicep"

info "Bicep デプロイを開始します（デプロイ名: ${PHASE2_DEPLOYMENT_NAME}）..."
echo ""

az deployment group create \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${PHASE2_DEPLOYMENT_NAME}" \
  --template-file "${APP_BICEP}" \
  --parameters env="${ENV}" location="${LOCATION}" \
  --output none

success "フェーズ2 デプロイが完了しました。"
echo ""

# ─── フェーズ2の出力を取得 ────────────────────────────────────
API_ENDPOINT=$(az deployment group show \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${PHASE2_DEPLOYMENT_NAME}" \
  --query "properties.outputs.apiEndpoint.value" \
  --output tsv 2>/dev/null || echo "(取得失敗)")

CA_NAME=$(az deployment group show \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${PHASE2_DEPLOYMENT_NAME}" \
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
echo "  【次の手順】Cosmos DB に初回メンバーと API キーを登録"
echo "──────────────────────────────────────────────────────────"
echo "  docs/deployment-guide.md のステップ4 を参照してください。"
echo ""
