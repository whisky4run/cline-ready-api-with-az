#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
# cline-ready-api-with-az — Bicep → ARM JSON ビルドスクリプト
#
# Bicep ファイルを ARM テンプレート（JSON）に変換して infra/arm/ に出力する。
# 生成された ARM JSON をリポジトリにコミットすることで、デプロイ環境に
# Bicep CLI がなくても安定したデプロイが可能になる。
#
# 使用方法: bash infra/build.sh
#
# 実行タイミング:
#   - 初回セットアップ時
#   - infra/*.bicep または infra/modules/*.bicep を変更したとき
#   ※ 変更後は arm/ をコミットし直すこと
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m    $*"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# ─── 前提条件チェック ─────────────────────────────────────────
if ! command -v az &>/dev/null; then
  error "Azure CLI が見つかりません。"
  error "  インストール: https://docs.microsoft.com/cli/azure/install-azure-cli"
  exit 1
fi

if ! az bicep version &>/dev/null; then
  info "Bicep CLI をインストールしています..."
  az bicep install
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     Bicep → ARM JSON ビルド                              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

mkdir -p "${SCRIPT_DIR}/arm"

# ─── main.bicep → arm/main.json ──────────────────────────────
info "main.bicep → arm/main.json をビルド中..."
az bicep build \
  --file "${SCRIPT_DIR}/main.bicep" \
  --outfile "${SCRIPT_DIR}/arm/main.json"
success "arm/main.json 生成完了"

# ─── app.bicep → arm/app.json ────────────────────────────────
info "app.bicep → arm/app.json をビルド中..."
az bicep build \
  --file "${SCRIPT_DIR}/app.bicep" \
  --outfile "${SCRIPT_DIR}/arm/app.json"
success "arm/app.json 生成完了"

echo ""
echo "──────────────────────────────────────────────────────────"
success "ARM テンプレート生成が完了しました。"
echo ""
echo "  次のステップ:"
echo "  1. infra/arm/ の変更をコミットしてください"
echo "     git add infra/arm/ && git commit -m 'build: update ARM templates'"
echo ""
echo "  2. デプロイは deploy.sh で行います（Bicep CLI 不要）"
echo "     bash infra/deploy.sh"
echo "──────────────────────────────────────────────────────────"
echo ""
