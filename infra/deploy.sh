#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# cline-ready-api-with-az (one-api) — デプロイスクリプト
#
# ARM テンプレート（arm/main.json, arm/app.json）を使用してデプロイする。
# Bicep CLI はデプロイ環境に不要。Bicep を変更した場合は build.sh を先に実行すること。
#
# 前提:
#   - リソースグループが存在すること（AI Foundry は ARM で自動作成される）
#   - infra/arm/main.json と infra/arm/app.json が存在すること（build.sh で生成）
#   - Docker Desktop が起動済みであること
#
# フェーズ1: arm/main.json をデプロイ（ACR / Container Apps 環境 / UAMI / 監視）
# フェーズ2: Docker イメージをビルドして ACR へプッシュ
# フェーズ3: arm/app.json をデプロイ（Container App）
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

# ARM テンプレートの存在確認
ARM_MAIN="${SCRIPT_DIR}/arm/main.json"
ARM_APP="${SCRIPT_DIR}/arm/app.json"
if [[ ! -f "${ARM_MAIN}" ]] || [[ ! -f "${ARM_APP}" ]]; then
  error "ARM テンプレートが見つかりません。"
  error "  先に build.sh を実行して ARM テンプレートを生成してください:"
  error "  bash infra/build.sh"
  exit 1
fi
success "ARM テンプレート: ${ARM_MAIN}, ${ARM_APP}"

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
    # 末尾のキャリッジリターンを削除
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
info "Azure AI Foundry でサポートされているモデル名を入力してください。"
echo ""
read -r -p "モデル名 [デフォルト: gpt-4.1-mini]: " MODEL_INPUT
AI_MODEL_NAME="${MODEL_INPUT:-gpt-4.1-mini}"
read -r -p "モデルバージョン [デフォルト: 2025-04-14]: " VERSION_INPUT
AI_MODEL_VERSION="${VERSION_INPUT:-2025-04-14}"
success "モデル: ${AI_MODEL_NAME} (${AI_MODEL_VERSION})"

echo ""

# ─── プロキシ API キー入力 ────────────────────────────────────
info "Cline からこの API に接続する際に使用するキーを設定します。"
info "任意の文字列を設定してください（例: sk-myteam-2024）"
while true; do
  read -r -s -p "プロキシ API キーを入力してください: " PROXY_API_KEY
  echo ""
  if [[ -z "${PROXY_API_KEY}" ]]; then
    warn "空のキーは設定できません。再入力してください。"
    continue
  fi
  if [[ ${#PROXY_API_KEY} -lt 8 ]]; then
    warn "8文字以上のキーを設定してください。"
    continue
  fi
  read -r -s -p "確認のため再入力してください: " PROXY_API_KEY_CONFIRM
  echo ""
  if [[ "${PROXY_API_KEY}" != "${PROXY_API_KEY_CONFIRM}" ]]; then
    warn "入力が一致しません。再入力してください。"
    continue
  fi
  success "プロキシ API キー: (${#PROXY_API_KEY} 文字を設定)"
  break
done

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
echo "  AI モデル          : ${AI_MODEL_NAME} (${AI_MODEL_VERSION})"
echo "  プロキシ API キー  : (${#PROXY_API_KEY} 文字)"
echo "  ARM テンプレート   : infra/arm/{main,app}.json"
echo "──────────────────────────────────────────────────────────"
echo ""

read -r -p "上記の設定でデプロイを開始しますか？ (y/N): " CONFIRM
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
AI_MODEL_DEPLOYED=$(get_output aiModelName)

info "AI Foundry API キーを取得中..."
AI_API_KEY=$(az cognitiveservices account keys list \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${AI_ACCOUNT_NAME}" \
  --query key1 \
  --output tsv)

if [[ -z "${AI_API_KEY}" ]]; then
  error "AI Foundry API キーの取得に失敗しました。アカウントの権限を確認してください。"
  exit 1
fi

echo "──────────────────────────────────────────────────────────"
echo "  フェーズ1 の出力"
echo "──────────────────────────────────────────────────────────"
echo "  ACR 名              : ${ACR_NAME}"
echo "  ACR ログインサーバー: ${ACR_LOGIN_SERVER}"
echo "  AI Foundry エンドポイント: ${AI_ENDPOINT}"
echo "  AI Foundry モデル   : ${AI_MODEL_DEPLOYED}"
echo "  AI Foundry API キー : (${#AI_API_KEY} 文字を取得)"
echo "──────────────────────────────────────────────────────────"
echo ""

# ═══════════════════════════════════════════════════════════════
# フェーズ2: コンテナイメージのビルドとプッシュ
# ═══════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════╗"
echo "║       コンテナイメージのビルドとプッシュ                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

info "ACR にログイン中..."
az acr login --name "${ACR_NAME}" --output none
success "ACR ログイン完了"

IMAGE_TAG="${ACR_LOGIN_SERVER}/cline-api:latest"

info "Docker イメージをビルド中: ${IMAGE_TAG} (linux/amd64)"
docker build \
  --platform linux/amd64 \
  -t "${IMAGE_TAG}" \
  -f "${REPO_ROOT}/src/ClineApiWithAz/Dockerfile" \
  "${REPO_ROOT}"
success "イメージビルド完了"

info "Docker イメージを ACR にプッシュ中..."
docker push "${IMAGE_TAG}"
success "イメージプッシュ完了"

echo ""

# ─── UAMI ロール伝播待機 ──────────────────────────────────────
# フェーズ1で割り当てた UAMI の AcrPull ロールが伝播するまで待機
ROLE_WAIT=90
info "UAMI ロール割り当ての伝播を待機中（${ROLE_WAIT}秒）..."
for i in $(seq "${ROLE_WAIT}" -1 1); do
  printf "\r  残り %3d 秒..." "$i"
  sleep 1
done
printf "\r  待機完了。                          \n"
success "ロール伝播待機が完了しました。"

echo ""

# ═══════════════════════════════════════════════════════════════
# フェーズ3: Container App デプロイ（arm/app.json）
# ═══════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           フェーズ3: Container App デプロイ              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

PHASE3_DEPLOYMENT_NAME="cline-api-phase3-$(date +%Y%m%d%H%M%S)"

info "ARM テンプレートをデプロイします（デプロイ名: ${PHASE3_DEPLOYMENT_NAME}）..."
echo ""

if ! az deployment group create \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${PHASE3_DEPLOYMENT_NAME}" \
  --template-file "${ARM_APP}" \
  --parameters \
    env="${ENV}" \
    location="${LOCATION}" \
    azureAiEndpoint="${AI_ENDPOINT}" \
    azureAiApiKey="${AI_API_KEY}" \
    apiKeyValue="${PROXY_API_KEY}" \
    modelName="${AI_MODEL_NAME}" \
  --output none; then

  error "フェーズ3 デプロイが失敗しました。Container App のログを確認します..."
  echo ""
  CA_NAME_FAILED=$(az containerapp list \
    --subscription "${SUBSCRIPTION_ID}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[?starts_with(name, 'ca-cline-api-')].name" \
    --output tsv 2>/dev/null | head -1 || true)

  if [[ -n "${CA_NAME_FAILED}" ]]; then
    info "Container App「${CA_NAME_FAILED}」のシステムログ（直近20件）:"
    az containerapp logs show \
      --subscription "${SUBSCRIPTION_ID}" \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${CA_NAME_FAILED}" \
      --type system \
      --tail 20 2>/dev/null || warn "ログを取得できませんでした。"
    echo ""
    info "リビジョン一覧:"
    az containerapp revision list \
      --subscription "${SUBSCRIPTION_ID}" \
      --resource-group "${RESOURCE_GROUP}" \
      --name "${CA_NAME_FAILED}" \
      --query "[].{Name:name, Active:properties.active, State:properties.runningState, Replicas:properties.replicas}" \
      --output table 2>/dev/null || true
  fi
  exit 1
fi

success "フェーズ3 デプロイが完了しました。"
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
