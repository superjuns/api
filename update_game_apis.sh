#!/bin/bash
# 批量更新游戏仓库中的API地址
# 用法: ./update_game_apis.sh <旧API_ID> <新API_ID>
# 示例: ./update_game_apis.sh auotd4g9jy kvgq7w0wzk

set -e

OLD_API="$1"
NEW_API="$2"

if [ -z "$OLD_API" ] || [ -z "$NEW_API" ]; then
    echo "用法: $0 <旧API_ID> <新API_ID>"
    echo "示例: $0 auotd4g9jy kvgq7w0wzk"
    exit 1
fi

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPOS_DIR="$(dirname "$BASE_DIR")"

echo "========================================"
echo "  批量更新游戏API地址"
echo "  旧: $OLD_API → 新: $NEW_API"
echo "========================================"
echo ""

UPDATED=0
SKIPPED=0

for repo_dir in "$REPOS_DIR"/*/; do
    repo_name=$(basename "$repo_dir")
    
    # 跳过api仓库本身和非git目录
    if [ "$repo_name" = "api" ] || [ ! -d "$repo_dir/.git" ]; then
        continue
    fi
    
    echo -n "🔍 检查 $repo_name ... "
    
    # 检查index.html是否包含旧API
    if [ ! -f "$repo_dir/index.html" ]; then
        echo "跳过（无index.html）"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    if ! grep -q "$OLD_API" "$repo_dir/index.html"; then
        echo "无匹配"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    
    # 统计替换次数
    count=$(grep -o "$OLD_API" "$repo_dir/index.html" | wc -l)
    echo "找到 $count 处，替换中..."
    
    cd "$repo_dir"
    
    # 执行替换（旧API和旧API/all都替换）
    sed -i '' "s|$OLD_API/all|$NEW_API/all|g" index.html
    sed -i '' "s|$OLD_API|$NEW_API|g" index.html
    
    # 验证
    if grep -q "$OLD_API" index.html; then
        echo "  ⚠️  仍有残留，请手动检查"
    else
        echo "  ✅ 替换完成"
    fi
    
    # Git提交
    export HOME=/root
    git add index.html
    git commit -m "chore: API地址更新 $OLD_API → $NEW_API"
    git push origin main
    
    echo "  🚀 已部署"
    echo ""
    UPDATED=$((UPDATED + 1))
done

echo ""
echo "========================================"
echo "  完成！"
echo "  更新仓库: $UPDATED 个"
echo "  跳过仓库: $SKIPPED 个"
echo "========================================"
