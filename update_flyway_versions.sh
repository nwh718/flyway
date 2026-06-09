#!/usr/bin/env bash
set -euo pipefail

NEW_VERSION="${NEW_VERSION:-12.8.1}"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)/flyway-database"
TARGET_MODULE="${1:-}"

if [ ! -d "$BASE_DIR" ]; then
  echo "[ERROR] Directory not found: $BASE_DIR"
  exit 1
fi

process_pom() {
  local pom_file="$1"
  local dir
  dir="$(dirname "$pom_file")"
  local module_name
  module_name="$(basename "$dir")"

  if [ ! -f "$pom_file" ]; then
    printf "  %-45s [失败] 文件不存在\n" "$module_name"
    return 1
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  local awk_status=0

  awk -v new_ver="$NEW_VERSION" '
    BEGIN { modified = 0 }
    {
      line = $0
      # 仅修改字面量 <version>X.Y.Z</version>，跳过 ${...} 变量引用
      if (match(line, /^([[:space:]]*)<version>([^$<][^<]*)<\/version>/, m)) {
        current_ver = m[3]
        if (current_ver != new_ver) {
          modified = 1
          line = m[1] "<version>" new_ver "</version>"
        }
      }
      # 同时支持 <flyway.version> 标签(若存在)
      if (match(line, /^([[:space:]]*)<flyway\.version>([^<]+)<\/flyway\.version>/, m)) {
        current_ver = m[3]
        if (current_ver != new_ver) {
          modified = 1
          line = m[1] "<flyway.version>" new_ver "</flyway.version>"
        }
      }
      print line
    }
    END { exit modified ? 1 : 0 }
  ' "$pom_file" > "$tmp_file" || awk_status=$?

  if diff -q "$pom_file" "$tmp_file" >/dev/null 2>&1; then
    rm -f "$tmp_file"
    printf "  %-45s [跳过] 版本已是 %s\n" "$module_name" "$NEW_VERSION"
    return 2
  fi

  local backup_file="${pom_file}.bak.$(date +%Y%m%d_%H%M%S)"
  if ! cp -f "$pom_file" "$backup_file"; then
    rm -f "$tmp_file"
    printf "  %-45s [失败] 备份失败\n" "$module_name"
    return 1
  fi

  if ! mv -f "$tmp_file" "$pom_file"; then
    rm -f "$tmp_file"
    printf "  %-45s [失败] 写入失败\n" "$module_name"
    return 1
  fi

  printf "  %-45s [成功] 已更新至 %s (备份: %s)\n" "$module_name" "$NEW_VERSION" "$(basename "$backup_file")"
  return 0
}

echo "========================================"
echo " Flyway 版本批量更新脚本"
echo " 目标版本 : $NEW_VERSION"
echo " 基础目录 : $BASE_DIR"
if [ -n "$TARGET_MODULE" ]; then
  echo " 指定模块 : $TARGET_MODULE"
fi
echo "========================================"
echo ""

total=0
success=0
skipped=0
failed=0

if [ -n "$TARGET_MODULE" ]; then
  target_pom="$BASE_DIR/$TARGET_MODULE/pom.xml"
  if [ ! -f "$target_pom" ]; then
    echo "[ERROR] 未找到模块: $TARGET_MODULE (期望路径: $target_pom)"
    echo ""
    echo "可用模块列表:"
    find "$BASE_DIR" -mindepth 1 -maxdepth 1 -type d | sort | while read -r d; do
      if [ -f "$d/pom.xml" ]; then
        echo "  - $(basename "$d")"
      fi
    done
    exit 1
  fi
  total=1
  process_pom "$target_pom" || status=$?
  status=${status:-0}
  case $status in
    0) success=1 ;;
    2) skipped=1 ;;
    1) failed=1 ;;
  esac
else
  pom_files=()
  while IFS= read -r -d '' pom_file; do
    pom_files+=("$pom_file")
  done < <(find "$BASE_DIR" -mindepth 2 -maxdepth 2 -type f -name "pom.xml" -print0 | sort -z)

  for pom_file in "${pom_files[@]}"; do
    total=$((total + 1))
    status=0
    process_pom "$pom_file" || status=$?
    case $status in
      0) success=$((success + 1)) ;;
      2) skipped=$((skipped + 1)) ;;
      1) failed=$((failed + 1)) ;;
    esac
  done
fi

echo ""
echo "========================================"
echo " 处理完成"
echo " 总数     : $total"
echo " 成功     : $success"
echo " 跳过     : $skipped"
echo " 失败     : $failed"
echo " 目标版本 : $NEW_VERSION"
echo "========================================"

[ "$failed" -eq 0 ]
