#!/bin/bash
# Supabase 免费项目保活脚本
# 用法：SUPABASE_URL=xxx SUPABASE_ANON_KEY=xxx bash supabase_keep_alive.sh
# 作用：每 5-6 天跑一次，避免 Supabase 免费版 7 天不活动被自动暂停

if [ -z "$SUPABASE_URL" ]; then
  echo "❌ 请设置环境变量 SUPABASE_URL（项目 URL，如 https://xxx.supabase.co）"
  exit 1
fi

if [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "❌ 请设置环境变量 SUPABASE_ANON_KEY（项目 anon key）"
  exit 1
fi

# 发一个轻量查询请求（白名单表只查 1 条，消耗极小）
# 如果白名单表名不同，把 white_list 改成你的表名
curl -s -X GET "$SUPABASE_URL/rest/v1/white_list?select=name&limit=1" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  -o /dev/null \
  -w "HTTP状态: %{http_code} | 耗时: %{time_total}s\n"

echo "✅ 保活请求完成 ($(date '+%Y-%m-%d %H:%M:%S'))"
