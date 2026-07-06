# 部署到腾讯云 49.232.232.27

## 1. 防火墙

腾讯云控制台 → 轻量服务器 → 防火墙，**放行 TCP 8787**（8788 仅本机，无需外网放行）。

## 2. 服务架构

| 服务 | 端口 | systemd 单元 |
|------|------|--------------|
| Node 体验服（鉴权/配额/API） | 8787 | `face-experience` |
| Python 25色部分析 | 8788（127.0.0.1） | `face-region25` |

数据目录：`/opt/face-diagnosis/experience-server/data/sessions/{sessionId}/`

## 3. 首次 / 更新部署

本地打包上传后 SSH 执行（或使用 CI）：

```bash
# 本地
cd tools/face_region_lab && tar czf /tmp/face_region_lab.tgz \
  --exclude=.venv --exclude=output \
  api_server.py pipeline.py color_analysis.py ling_shu_rules.py report_builder.py \
  grid_from_68.py landmark_provider.py region_mapper.py renderer.py validate.py \
  regions_25.json requirements.txt models/

cd tools/experience-server && tar czf /tmp/experience-server-update.tgz \
  --exclude=node_modules --exclude=data --exclude=.env \
  server.js package.json whitelist.json start-with-region25.sh

scp /tmp/face_region_lab.tgz /tmp/experience-server-update.tgz root@49.232.232.27:/tmp/
```

服务器：

```bash
# 系统库（MediaPipe / OpenCV 无头服务器必需）
dnf install -y python3 python3-pip python3-devel mesa-libGL mesa-libEGL

mkdir -p /opt/face-diagnosis/face_region_lab
tar xzf /tmp/face_region_lab.tgz -C /opt/face-diagnosis/face_region_lab
cd /opt/face-diagnosis/face_region_lab
python3 -m venv .venv && .venv/bin/pip install -U pip && .venv/bin/pip install -r requirements.txt

cd /opt/face-diagnosis/experience-server
tar xzf /tmp/experience-server-update.tgz
npm install --omit=dev

systemctl restart face-region25 face-experience
```

## 4. 环境变量

`/opt/face-diagnosis/experience-server/.env`：

```
PORT=8787
DAILY_FREE_LIMIT=2
DASHSCOPE_API_KEY=sk-xxx   # 文案生成可选；25色部 Lab 分析不依赖
```

## 5. 验证

```bash
curl -s http://127.0.0.1:8788/health
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8787/v1/auth/status   # 401 正常
```

## 6. App

`AppConstants.ets` → `http://49.232.232.27:8787`，体验模式走 `/v1/region25/analyze`。

白名单见 `whitelist.json`。
