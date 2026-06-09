#!/bin/bash

# 目标版本
NEW_VERSION="12.8.1"
BASE_DIR="flyway-database"

# 检查基础目录是否存在
if [ ! -d "$BASE_DIR" ]; then
    echo "Error: Directory $BASE_DIR not found in current path."
    exit 1
fi

# 接收可选的单个模块参数
TARGET_MODULE=$1

# 收集需要处理的 pom.xml 文件
POM_FILES=()
if [ -n "$TARGET_MODULE" ]; then
    POM_FILES=("$BASE_DIR/$TARGET_MODULE/pom.xml")
    if [ ! -f "${POM_FILES[0]}" ]; then
        echo "Failed: ${POM_FILES[0]} (File not found)"
        exit 1
    fi
else
    # 查找 flyway-database 下所有直接子目录中的 pom.xml
    for f in "$BASE_DIR"/*/pom.xml; do
        [ -e "$f" ] && POM_FILES+=("$f")
    done
fi

if [ ${#POM_FILES[@]} -eq 0 ]; then
    echo "No pom.xml files found."
    exit 1
fi

for pom in "${POM_FILES[@]}"; do
    if [ ! -f "$pom" ]; then
        echo "Failed: $pom (File not found)"
        continue
    fi

    # 自动备份原文件
    cp "$pom" "$pom.bak"
    if [ $? -ne 0 ]; then
        echo "Failed: $pom (Could not create backup)"
        continue
    fi

    # 使用 awk 替换第一个 <flyway.version> 或 <version>（忽略带有 ${} 变量引用的版本）
    awk -v new_ver="$NEW_VERSION" '
    BEGIN { replaced = 0; changed = 0 }
    {
        if (replaced == 0 && match($0, /<flyway\.version>[^<]*<\/flyway\.version>/)) {
            old_line = $0
            sub(/<flyway\.version>[^<]*<\/flyway\.version>/, "<flyway.version>" new_ver "</flyway.version>")
            if (old_line != $0) changed = 1
            replaced = 1
        }
        else if (replaced == 0 && match($0, /<version>[^<]*<\/version>/) && $0 !~ /\$\{.*\}/) {
            old_line = $0
            sub(/<version>[^<]*<\/version>/, "<version>" new_ver "</version>")
            if (old_line != $0) changed = 1
            replaced = 1
        }
        print $0
    }
    END {
        if (changed) exit 0; else exit 1;
    }
    ' "$pom" > "${pom}.tmp"
    
    AWK_STATUS=$?

    if [ $AWK_STATUS -eq 0 ]; then
        mv "${pom}.tmp" "$pom"
        echo "Success: $pom (Updated to $NEW_VERSION)"
    else
        rm "${pom}.tmp"
        rm -f "${pom}.bak"
        # 判断是已更新还是找不到标签
        if grep -E -q "<version>$NEW_VERSION</version>|<flyway\.version>$NEW_VERSION</flyway\.version>" "$pom"; then
            echo "Skipped: $pom (Already up to date)"
        else
            echo "Skipped/Failed: $pom (Target tag not found or no changes made)"
        fi
    fi
done
