#!/bin/bash
# 启动体验服 + 25色部 Python 分析 API
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAB="$ROOT/face_region_lab"
SERVER="$ROOT/experience-server"

export REGION25_DATA_DIR="$SERVER/data/sessions"
export REGION25_API_PORT="${REGION25_API_PORT:-8788}"

if [ ! -d "$LAB/.venv" ]; then
  echo "请先创建 Python 虚拟环境: cd tools/face_region_lab && python3 -m venv .venv && pip install -r requirements.txt"
  exit 1
fi

echo "[start] Python region25 API :8788"
"$LAB/.venv/bin/python" "$LAB/api_server.py" &
PY_PID=$!

cleanup() {
  kill "$PY_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "[start] Node experience server :${PORT:-8787}"
cd "$SERVER"
npm start
