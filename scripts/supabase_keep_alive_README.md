# Supabase 免费版保活方案

Supabase 免费版项目 **7 天不活动会自动暂停**，需要手动去后台恢复。以下几种方案任选一种：

---

## 方案一：GitHub Actions 定时触发（推荐，零成本）

> ⚠️ 需要你的 GitHub Token 有 `workflow` 权限才能推送 workflow 文件。
> 如果 token 没有这个权限，用方案二或三。

1. 在 api 仓库 `.github/workflows/` 下新建 `supabase-keep-alive.yml`：

```yaml
name: Supabase Keep Alive
on:
  schedule:
    - cron: '0 0 */5 * *'   # 每 5 天跑一次
  workflow_dispatch:
jobs:
  keep-alive:
    runs-on: ubuntu-latest
    steps:
      - name: Ping Supabase
        env:
          URL: ${{ secrets.SUPABASE_PROJECT_URL }}
          KEY: ${{ secrets.SUPABASE_ANON_KEY }}
        run: |
          curl -s "$URL/rest/v1/white_list?limit=1" \
            -H "apikey: $KEY" \
            -H "Authorization: Bearer $KEY" \
            -w "Status: %{http_code}\n"
```

2. 仓库 Settings → Secrets and variables → Actions，添加两个 Secret：
   - `SUPABASE_PROJECT_URL`：你的项目 URL（如 `https://xxx.supabase.co`）
   - `SUPABASE_ANON_KEY`：项目的 anon key

---

## 方案二：腾讯云函数 + 定时触发器（国内稳定）

1. 腾讯云函数 → 新建函数（Node.js 或 Python）
2. 函数代码里发一个 HTTP GET 请求到 Supabase
3. 设置定时触发器：每 5 天触发一次
4. 免费额度内够用

---

## 方案三：服务器 cron 定时任务

如果你有自己的服务器，直接用 crontab：

```bash
# 每 5 天凌晨 3 点跑一次
0 3 */5 * * SUPABASE_URL=https://xxx.supabase.co SUPABASE_ANON_KEY=eyJhbG... bash /path/to/supabase_keep_alive.sh
```

---

## 方案四：手机设提醒手动点一下（最简单）

每周日打开 Supabase 后台点一下项目，或者打开一次用了 Supabase 的游戏页面。
适合项目少、懒得折腾的情况。

---

## 脚本使用

```bash
# 直接跑
SUPABASE_URL=https://xxx.supabase.co SUPABASE_ANON_KEY=eyJhbG... bash scripts/supabase_keep_alive.sh
```
