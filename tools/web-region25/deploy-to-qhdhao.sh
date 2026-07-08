#!/usr/bin/env bash
# 一键部署：体验服 CORS + 网页版 sezhen + qhdhao.cn 首页链接
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SERVER="${DEPLOY_HOST:-root@49.232.232.27}"
WEB_ROOT="/var/www/zuwa-blog"
SEZHEN_DIR="$WEB_ROOT/sezhen"
EXP_DIR="/opt/face-diagnosis/experience-server"
LAB_DIR="/opt/face-diagnosis/face_region_lab"

SSH_OPTS=(-o StrictHostKeyChecking=accept-new)
if [[ -n "${SSHPASS:-}" ]] && command -v sshpass >/dev/null 2>&1; then
  SSH=(sshpass -e ssh "${SSH_OPTS[@]}")
  SCP=(sshpass -e scp "${SSH_OPTS[@]}")
else
  SSH=(ssh "${SSH_OPTS[@]}")
  SCP=(scp "${SSH_OPTS[@]}")
fi

echo "==> 打包网页版 sezhen"
TMP=$(mktemp -d)
tar czf "$TMP/web-region25.tgz" -C "$ROOT/tools" web-region25

echo "==> 打包体验服与 Python 更新"
tar czf "$TMP/experience-update.tgz" -C "$ROOT/tools/experience-server" \
  server.js lib/region25Enrich.js lib/usageStats.js data/ancient_knowledge.json
tar czf "$TMP/face-lab-update.tgz" -C "$ROOT/tools/face_region_lab" \
  grid_from_68.py renderer.py regions_25.json validate_grid_visual.py \
  pipeline.py report_builder.py gender_estimate.py region_mapper.py \
  landmark_provider.py color_analysis.py ling_shu_rules.py \
  validate.py api_server.py

echo "==> 上传到 $SERVER"
"${SCP[@]}" "$TMP/web-region25.tgz" "$TMP/experience-update.tgz" "$TMP/face-lab-update.tgz" "$SERVER:/tmp/"
"${SCP[@]}" "$ROOT/docs/agc/privacy-policy.html" "$SERVER:/tmp/privacy-policy.html"

echo "==> 远程安装"
"${SSH[@]}" "$SERVER" bash -s <<'REMOTE'
set -euo pipefail
WEB_ROOT="/var/www/zuwa-blog"
SEZHEN_DIR="$WEB_ROOT/sezhen"
EXP_DIR="/opt/face-diagnosis/experience-server"
LAB_DIR="/opt/face-diagnosis/face_region_lab"
NGINX_CONF="/etc/nginx/conf.d/zuwa-blog.conf"

mkdir -p "$SEZHEN_DIR"
tar xzf /tmp/web-region25.tgz -C /tmp
rm -rf "$SEZHEN_DIR"/*
cp -a /tmp/web-region25/. "$SEZHEN_DIR/"
cp /tmp/privacy-policy.html "$SEZHEN_DIR/privacy.html"
chown -R nginx:nginx "$SEZHEN_DIR"

tar xzf /tmp/experience-update.tgz -C "$EXP_DIR"
tar xzf /tmp/face-lab-update.tgz -C "$LAB_DIR"

# Nginx：/sezhen/ 与 /face-api/ 反代（^~ 防止静态 *.jpg 规则抢走标注图）
if grep -q 'location /face-api/' "$NGINX_CONF" && ! grep -q 'location \^~ /face-api/' "$NGINX_CONF"; then
  sed -i 's|location /face-api/|location ^~ /face-api/|' "$NGINX_CONF"
fi

if ! grep -q 'location /sezhen/' "$NGINX_CONF"; then
  sed -i '/location \/posts\//i\
    location ^~ /face-api/ {\
        proxy_pass http://127.0.0.1:8787/;\
        proxy_set_header Host $host;\
        proxy_read_timeout 120s;\
        client_max_body_size 20m;\
    }\
\
    location /sezhen/ {\
        alias /var/www/zuwa-blog/sezhen/;\
        index index.html;\
        try_files $uri $uri/ /sezhen/index.html;\
    }\
' "$NGINX_CONF"
fi

# 首页加链接（幂等）
INDEX="$WEB_ROOT/index.html"
MARK='二十五明堂色诊 · 网页版'
if ! grep -q "$MARK" "$INDEX"; then
  sed -i '/<p class="subtitle">/a\
            <p style="margin:16px 0 8px;"><a href="/sezhen/" style="color:#8b4513;font-weight:bold;text-decoration:none;padding:8px 16px;border:1px solid #c4a574;border-radius:8px;display:inline-block;">二十五明堂色诊 · 网页版</a> <span style="color:#999;font-size:12px;">古籍养生文化自测 · 非医疗</span></p>' "$INDEX"
fi

nginx -t
systemctl reload nginx
systemctl restart face-region25
systemctl restart face-experience

echo "--- 健康检查 ---"
curl -sf http://127.0.0.1:8788/health
echo
curl -s -o /dev/null -w "face-experience HTTP %{http_code}\n" http://127.0.0.1:8787/v1/auth/status
curl -s -o /dev/null -w "sezhen page HTTP %{http_code}\n" -H 'Host: qhdhao.cn' http://127.0.0.1/sezhen/
curl -s -o /dev/null -w "face-api proxy HTTP %{http_code}\n" -H 'Host: qhdhao.cn' http://127.0.0.1/face-api/v1/auth/status
# 标注图须走反代（带 .jpg 后缀，易被静态规则拦截；^~ 修复后应为 401 无 token / 200 有 token）
curl -s -o /dev/null -w "face-api image route HTTP %{http_code}\n" -H 'Host: qhdhao.cn' http://127.0.0.1/face-api/v1/region25/image/00000000-0000-0000-0000-000000000000/annotated.jpg

# CORS 头抽检
curl -sI -H 'Origin: http://qhdhao.cn' http://127.0.0.1:8787/v1/auth/status | grep -i access-control || true
REMOTE

rm -rf "$TMP"
echo "==> 部署完成"
echo "    网页：http://qhdhao.cn/sezhen/"
echo "    隐私政策：http://qhdhao.cn/sezhen/privacy.html"
echo "    首页已加链接（若尚未存在）"
