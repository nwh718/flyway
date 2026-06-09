#!/usr/bin/env bash
#
# update_flyway_version.sh
# 批量将 flyway-database 子模块的 Flyway 版本统一修改为目标版本。
#
# 用法:
#   ./update_flyway_version.sh [MODULE_NAME]
#
#   不带参数: 更新所有子模块
#   带参数:   仅更新指定子模块 (如 flyway-database-postgresql)
#
# 目标版本可通过 TARGET_VERSION 环境变量覆盖，默认为 12.8.1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_VERSION="${TARGET_VERSION:-12.8.1}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

SUCCESS_COUNT=0
SKIP_COUNT=0
FAIL_COUNT=0

usage() {
    echo "用法: $0 [MODULE_NAME]"
    echo ""
    echo "批量将 flyway-database 子模块的 Flyway 版本统一修改为 ${TARGET_VERSION}"
    echo ""
    echo "可选参数:"
    echo "  MODULE_NAME    指定单个子模块目录名 (如 flyway-database-postgresql)"
    echo ""
    echo "可用子模块列表:"
    for dir in "$SCRIPT_DIR"/flyway-*/; do
        echo "  - $(basename "$dir")"
    done
    exit 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

# ──────────────────────────────────────────────
# 收集待处理的子模块
# ──────────────────────────────────────────────
MODULES=()
if [[ -n "${1:-}" ]]; then
    MODULE_DIR="$SCRIPT_DIR/$1"
    if [[ ! -d "$MODULE_DIR" ]]; then
        echo -e "${COLOR_RED}错误: 子模块 '$1' 不存在${COLOR_RESET}"
        exit 1
    fi
    MODULES+=("$1")
else
    for dir in "$SCRIPT_DIR"/flyway-*/; do
        MODULES+=("$(basename "$dir")")
    done
fi

if [[ ${#MODULES[@]} -eq 0 ]]; then
    echo -e "${COLOR_YELLOW}警告: 没有找到任何子模块${COLOR_RESET}"
    exit 0
fi

echo "============================================"
echo "  Flyway 版本批量更新工具"
echo "  目标版本: ${TARGET_VERSION}"
echo "  目标模块数: ${#MODULES[@]}"
echo "  脚本目录: ${SCRIPT_DIR}"
echo "============================================"
echo ""

# ──────────────────────────────────────────────
# 逐模块处理
# ──────────────────────────────────────────────
for module in "${MODULES[@]}"; do
    POM_FILE="$SCRIPT_DIR/$module/pom.xml"

    if [[ ! -f "$POM_FILE" ]]; then
        echo -e "[${COLOR_RED}FAIL${COLOR_RESET}] ${module}: pom.xml 不存在"
        ((FAIL_COUNT++))
        continue
    fi

    # 提取 <parent> 块中的当前版本
    CURRENT_VERSION=$(sed -n '/<parent>/,/<\/parent>/ s|.*<version>\([0-9.]*\)</version>.*|\1|p' "$POM_FILE" | head -1)

    if [[ -z "$CURRENT_VERSION" ]]; then
        echo -e "[${COLOR_RED}FAIL${COLOR_RESET}] ${module}: 无法解析 <parent> 中的版本号"
        ((FAIL_COUNT++))
        continue
    fi

    if [[ "$CURRENT_VERSION" == "$TARGET_VERSION" ]]; then
        echo -e "[${COLOR_YELLOW}SKIP${COLOR_RESET}] ${module}: 版本已是 ${TARGET_VERSION}，无需修改"
        ((SKIP_COUNT++))
        continue
    fi

    # 备份原文件
    BACKUP_FILE="${POM_FILE}.${TIMESTAMP}.bak"
    if ! cp "$POM_FILE" "$BACKUP_FILE"; then
        echo -e "[${COLOR_RED}FAIL${COLOR_RESET}] ${module}: 备份失败"
        ((FAIL_COUNT++))
        continue
    fi

    # 仅在 <parent> 块内替换版本号，避免影响其他 <version> 标签
    if sed -i'' -e "/<parent>/,/<\/parent>/ s|<version>${CURRENT_VERSION}</version>|<version>${TARGET_VERSION}</version>|" "$POM_FILE"; then
        # 验证修改结果
        NEW_VERSION=$(sed -n '/<parent>/,/<\/parent>/ s|.*<version>\([0-9.]*\)</version>.*|\1|p' "$POM_FILE" | head -1)
        if [[ "$NEW_VERSION" == "$TARGET_VERSION" ]]; then
            echo -e "[${COLOR_GREEN} OK ${COLOR_RESET}] ${module}: ${CURRENT_VERSION} -> ${TARGET_VERSION}  (备份: ${POM_FILE}.${TIMESTAMP}.bak)"
            ((SUCCESS_COUNT++))
        else
            # 回滚
            mv "$BACKUP_FILE" "$POM_FILE"
            echo -e "[${COLOR_RED}FAIL${COLOR_RESET}] ${module}: 版本替换后验证失败, 已回滚"
            ((FAIL_COUNT++))
        fi
    else
        echo -e "[${COLOR_RED}FAIL${COLOR_RESET}] ${module}: sed 命令执行失败"
        ((FAIL_COUNT++))
    fi
done

# ──────────────────────────────────────────────
# 汇总报告
# ──────────────────────────────────────────────
echo ""
echo "============================================"
echo "  执行结果汇总"
echo "============================================"
echo -e "  成功: ${COLOR_GREEN}${SUCCESS_COUNT}${COLOR_RESET}"
echo -e "  跳过: ${COLOR_YELLOW}${SKIP_COUNT}${COLOR_RESET}"
echo -e "  失败: ${COLOR_RED}${FAIL_COUNT}${COLOR_RESET}"
echo "  总计: $(( SUCCESS_COUNT + SKIP_COUNT + FAIL_COUNT ))"
echo "============================================"