#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# cline-ready-api-with-az — リソース削除スクリプト
#
# project=cline-ready-api-with-az タグが付いたリソースのみ削除します。
# 手動作成済みの AI Foundry など、タグのないリソースは削除されません。
#
# 使用方法: bash infra/destroy.sh
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# ─── 色付きメッセージ ─────────────────────────────────────────
info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# ─── az CLI チェック ──────────────────────────────────────────
if ! command -v az &>/dev/null; then
  error "Azure CLI が見つかりません。"
  exit 1
fi

# ─── ログイン確認 ─────────────────────────────────────────────
if ! az account show &>/dev/null; then
  info "Azure にログインしていません。ログインします..."
  az login
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     cline-ready-api-with-az  リソース削除               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
info "削除対象: project=cline-ready-api-with-az タグ付きリソースのみ"
info "AI Foundry など手動作成リソースは削除されません。"
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
    success "サブスクリプション「${SUBSCRIPTION_NAME}」（${SUBSCRIPTION_ID}）を選択しました。"
    break
  else
    error "サブスクリプション「${SUBSCRIPTION_INPUT}」が見つかりません。再入力してください。"
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
  exit 1
fi

for i in "${!RG_LIST[@]}"; do
  IFS=$'\t' read -r rg_name rg_loc <<< "${RG_LIST[$i]}"
  printf "  %2d) %-45s %s\n" "$((i+1))" "${rg_name}" "${rg_loc}"
done
echo ""

while true; do
  read -r -p "削除するリソースグループ番号を入力してください (1-${#RG_LIST[@]}): " RG_IDX
  if [[ "${RG_IDX}" =~ ^[0-9]+$ ]] && (( RG_IDX >= 1 && RG_IDX <= ${#RG_LIST[@]} )); then
    IFS=$'\t' read -r RESOURCE_GROUP _ <<< "${RG_LIST[$((RG_IDX-1))]}"
    break
  else
    warn "1〜${#RG_LIST[@]} の範囲で番号を入力してください。"
  fi
done

echo ""

# ─── タグ付きリソース一覧の表示 ──────────────────────────────
TAG_FILTER="project=cline-ready-api-with-az"

info "リソースグループ「${RESOURCE_GROUP}」内の削除対象リソース（タグ: ${TAG_FILTER}）:"
echo ""

TAGGED_RESOURCES=$(az resource list \
  --subscription "${SUBSCRIPTION_ID}" \
  --resource-group "${RESOURCE_GROUP}" \
  --tag "${TAG_FILTER}" \
  --query "[].{Name:name, Type:type}" \
  --output table 2>/dev/null)

if [[ -z "${TAGGED_RESOURCES}" ]] || [[ "${TAGGED_RESOURCES}" == *"(empty)"* ]]; then
  warn "タグ付きリソースが見つかりませんでした（タグ追加前のデプロイの可能性）。"
  echo ""
  info "リソースグループ内の全リソース:"
  az resource list \
    --subscription "${SUBSCRIPTION_ID}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[].{Name:name, Type:type}" \
    --output table 2>/dev/null
  echo ""
  warn "代替手段: リソースグループ「${RESOURCE_GROUP}」ごと削除しますか？"
  warn "※ AI Foundry など手動作成リソースも削除されます。"
  echo ""
  read -r -p "リソースグループごと削除する場合は「${RESOURCE_GROUP}」と入力してください（スキップは Enter）: " RG_DELETE_CONFIRM
  if [[ "${RG_DELETE_CONFIRM}" == "${RESOURCE_GROUP}" ]]; then
    info "リソースグループ「${RESOURCE_GROUP}」を削除しています..."
    az group delete \
      --subscription "${SUBSCRIPTION_ID}" \
      --name "${RESOURCE_GROUP}" \
      --yes \
      --no-wait
    success "削除リクエストを送信しました。バックグラウンドで削除が進行中です。"
  else
    info "削除をスキップしました。"
  fi
  exit 0
fi

echo "${TAGGED_RESOURCES}"
echo ""

# ─── 警告と確認 ───────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────"
warn "警告: 上記リソースを削除します。この操作は元に戻せません！"
echo "──────────────────────────────────────────────────────────"
echo "  サブスクリプション : ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"
echo "  リソースグループ   : ${RESOURCE_GROUP}"
echo "  ※ タグのないリソース（AI Foundry 等）は削除されません"
echo "──────────────────────────────────────────────────────────"
echo ""

read -r -p "本当に削除しますか？ (y/N): " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  info "削除をキャンセルしました。"
  exit 0
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# タグ付きリソースを依存関係の順に削除
# Container App → CA環境 → ACR → AppInsights → LogAnalytics → UAMI
# ═══════════════════════════════════════════════════════════════
RESOURCE_TYPES_IN_ORDER=(
  "Microsoft.App/containerApps"
  "Microsoft.App/managedEnvironments"
  "Microsoft.ContainerRegistry/registries"
  "Microsoft.Insights/components"
  "Microsoft.OperationalInsights/workspaces"
  "Microsoft.ManagedIdentity/userAssignedIdentities"
)

delete_by_type() {
  local resource_type="$1"
  local ids
  ids=$(az resource list \
    --subscription "${SUBSCRIPTION_ID}" \
    --resource-group "${RESOURCE_GROUP}" \
    --tag "${TAG_FILTER}" \
    --resource-type "${resource_type}" \
    --query "[].id" \
    --output tsv 2>/dev/null || true)

  if [[ -z "${ids}" ]]; then
    return 0
  fi

  while IFS= read -r resource_id; do
    [[ -z "${resource_id}" ]] && continue
    local resource_name
    resource_name=$(basename "${resource_id}")
    info "削除中: ${resource_name} (${resource_type})"
    az resource delete \
      --subscription "${SUBSCRIPTION_ID}" \
      --ids "${resource_id}" \
      --verbose 2>&1 | grep -E "^(az|ERROR|WARNING)" || true
    success "  削除完了: ${resource_name}"
  done <<< "${ids}"
}

echo "╔══════════════════════════════════════════════════════════╗"
echo "║           タグ付きリソースの削除                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

for resource_type in "${RESOURCE_TYPES_IN_ORDER[@]}"; do
  delete_by_type "${resource_type}"
done

success "すべてのタグ付きリソースを削除しました。"
echo ""
