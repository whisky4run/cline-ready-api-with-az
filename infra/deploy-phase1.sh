#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# cline-ready-api-with-az — フェーズ1: インフラ構築
#
# 企業プロキシ環境でのデプロイ分割方式
# このスクリプトではフェーズ1（インフラ構築）のみを実行
#
# フェーズ1 の内容:
#   - ACR (Azure Container Registry) 作成
#   - Container Apps 環境作成
#   - Managed Identity (UAMI) 作成
#   - AI Foundry デプロイ
#
# 実行環境: ローカルマシン（Docker 不要）
# 前提条件:
#   - Azure CLI がインストール済み
#   - Azure にログイン済み
#   - infra/arm/main.json が存在
#
# 実行手順:
#   1. ローカルマシンでこのスクリプトを実行
#   2. 出力情報を控える（フェーズ2で使用）
#   3. Cloud Shell で deploy-cloud-shell.sh を実行
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

# ─── 前提条件チェック ──────────────────────────────────────────
info "前提条件をチェックしています..."

if ! command -v az &>/dev/null; then
  error "Azure CLI が見つかりません。"
  exit 1
fi

# ⚠️ 重要: ARM テンプレートが既に存在する場合、Bicep コンパイルをスキップ
# Bicep コンパイルはプロキシの影響を受けるため、既存の ARM JSON を使用
ARM_MAIN="${SCRIPT_DIR}/arm/main.json"
if [[ ! -f "${ARM_MAIN}" ]]; then
  error "ARM テンプレートが見つかりません: ${ARM_MAIN}"
  error ""
  error "【選択肢1】既にコンパイル済みの場合"
  error "  →このスクリプトはそのまま使用できます（ARM JSON を使用します）"
  error ""
  error "【選択肢2】Bicep から再ビルドが必要な場合"
  error "  →プロキシの影響を受けないため、Cloud Shell でコンパイルしてください:"
  error "    az bicep build --file infra/main.bicep --outfile infra/arm/main.json"
  exit 1
fi

success "ARM テンプレート確認: ${ARM_MAIN}"

if ! az account show &>/dev/null; then
  info "Azure にログインしていません。ログインします..."
  az login
fi

success "前提条件チェック完了"
echo ""
info "⚠️  このスクリプトは既存の ARM テンプレートを使用します"
info "    (Bicep コンパイルはスキップ → プロキシの影響を回避)"
echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  フェーズ1: インフラ構築セットアップ                     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

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
    success "サブスクリプション「${SUBSCRIPTION_NAME}」を選択しました。"
    break
  else
    error "サブスクリプション「${SUBSCRIPTION_INPUT}」が見つかりません。"
  fi
done

echo ""

# ─── リソースグループ選択 ─────────────────────────────────────
info "利用可能なリソースグループ一覧:"
echo ""

RG_LIST=()
while IFS=$'\t' read -r rg_name rg_loc; do
  RG_LIST+=("${rg_name}"$'\t'"${rg_loc}")
done < <(az group list --subscription "${SUBSCRIPTION_ID}" \
  --query "sort_by([], &name)[].[name, location]" --output tsv)

if [[ ${#RG_LIST[@]} -eq 0 ]]; then
  error "リソースグループが見つかりません。"
  error "先に Azure Portal でリソースグループを作成してください。"
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
    LOCATION="${LOCATION%$'\r'}"
    success "リソースグループ: ${RESOURCE_GROUP} (${LOCATION})"
    break
  else
    warn "1〜${#RG_LIST[@]} の範囲で番号を入力してください。"
  fi
done

echo ""

# ─── AI モデル指定 ────────────────────────────────────────────
info "デプロイする AI モデルを指定します。"
echo ""
read -r -p "モデル名 [デフォルト: gpt-4.1-mini]: " MODEL_INPUT
AI_MODEL_NAME="${MODEL_INPUT:-gpt-4.1-mini}"
read -r -p "モデルバージョン [デフォルト: 2025-04-14]: " VERSION_INPUT
AI_MODEL_VERSION="${VERSION_INPUT:-2025-04-14}"
success "モデル: ${AI_MODEL_NAME} (${AI_MODEL_VERSION})"

echo ""

# ─── 環境選択 ─────────────────────────────────────────────────
while true; do
  read -r -p "デプロイ環境を選択してください (dev/prod) [デフォルト: dev]: " ENV_INPUT
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
echo "  フェーズ1 デプロイ設定の確認"
echo "──────────────────────────────────────────────────────────"
echo "  サブスクリプション : ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
echo "  リソースグループ   : ${RESOURCE_GROUP}"
echo "  リージョン         : ${LOCATION}"
echo "  環境               : ${ENV}"
echo "  AI モデル          : ${AI_MODEL_NAME} (${AI_MODEL_VERSION})"
echo "  ARM テンプレート   : ${ARM_MAIN}"
echo "──────────────────────────────────────────────────────────"
echo ""

read -r -p "上記の設定でフェーズ1 をデプロイしますか？ (y/N): " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  info "デプロイをキャンセルしました。"
  exit 0
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# フェーズ1: インフラ構築（arm/main.json）
# ═══════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           フェーズ1: インフラ構築                        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

PHASE1_DEPLOYMENT_NAME="cline-api-phase1-$(date +%Y%m%d%H%M%S)"

info "ARM テンプレートをデプロイします（デプロイ名: ${PHASE1_DEPLOYMENT_NAME}）..."
echo ""

az deployment group create \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${PHASE1_DEPLOYMENT_NAME}" \
  --template-file "${ARM_MAIN}" \
  --parameters env="${ENV}" location="${LOCATION}" \
    modelName="${AI_MODEL_NAME}" modelVersion="${AI_MODEL_VERSION}" \
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

ACR_LOGIN_SERVER=$(get_output acrLoginServer)
ACR_NAME=$(get_output acrName)
AI_ENDPOINT=$(get_output aiEndpoint)
AI_ACCOUNT_NAME=$(get_output aiAccountName)

info "AI Foundry API キーを取得中..."
AI_API_KEY=$(az cognitiveservices account keys list \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AI_ACCOUNT_NAME}" \
  --query key1 \
  --output tsv)

if [[ -z "${AI_API_KEY}" ]]; then
  error "AI Foundry API キーの取得に失敗しました。"
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           フェーズ1 完了！                               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "──────────────────────────────────────────────────────────"
echo "  フェーズ1 の出力（控えておいてください）"
echo "──────────────────────────────────────────────────────────"
echo "  ACR 名              : ${ACR_NAME}"
echo "  ACR ログインサーバー: ${ACR_LOGIN_SERVER}"
echo "  AI Foundry エンドポイント: ${AI_ENDPOINT}"
echo "  AI Foundry API キー : ${AI_API_KEY}"
echo "  AI Foundry モデル   : ${AI_MODEL_NAME}"
echo "──────────────────────────────────────────────────────────"
echo ""
echo "  💾 以下の情報を控えてください（フェーズ2で使用）:"
echo ""
echo "    SUBSCRIPTION_ID=${SUBSCRIPTION_ID}"
echo "    RESOURCE_GROUP=${RESOURCE_GROUP}"
echo "    ACR_NAME=${ACR_NAME}"
echo "    AI_ENDPOINT=${AI_ENDPOINT}"
echo "    AI_API_KEY=${AI_API_KEY}"
echo "    AI_MODEL_NAME=${AI_MODEL_NAME}"
echo ""
echo "──────────────────────────────────────────────────────────"
echo ""
echo "  🚀 次のステップ:"
echo ""
echo "  1. Azure Portal で Cloud Shell を起動"
echo "  2. リポジトリをクローン:"
echo "     git clone --branch one-api https://github.com/whisky4run/cline-ready-api-with-az.git"
echo "     cd cline-ready-api-with-az"
echo ""
echo "  3. Cloud Shell でフェーズ2&3 を実行:"
echo "     bash infra/deploy-cloud-shell.sh"
echo ""
echo "     上記の情報を入力してください。"
echo "──────────────────────────────────────────────────────────"
echo ""
