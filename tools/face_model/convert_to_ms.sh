#!/usr/bin/env bash
# UltraFace ONNX → MindSpore Lite .ms → 复制为 App 的 mtcnn.om
#
# 使用前：
#   1. 从华为 DevEco / MindSpore Lite 套件安装 converter_lite
#   2. 将 CONVERTER_LITE 改为本机 converter_lite 可执行文件路径
#   3. 先运行 download_ultraface.py

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ONNX="${SCRIPT_DIR}/output/version-RFB-320.onnx"
OUT_MS="${SCRIPT_DIR}/output/mtcnn"
APP_MODEL_DIR="${SCRIPT_DIR}/../../entry/src/main/resources/rawfile/models"

# TODO: 改为你本机 MindSpore Lite 转换器路径（DevEco SDK 或 mindspore-lite 发布包）
CONVERTER_LITE="${CONVERTER_LITE:-converter_lite}"

if [[ ! -f "$ONNX" ]]; then
  echo "缺少 $ONNX，请先: python3 download_ultraface.py"
  exit 1
fi

if ! command -v "$CONVERTER_LITE" &>/dev/null; then
  echo "未找到 converter_lite。请设置环境变量 CONVERTER_LITE=绝对路径"
  echo "参考: docs/MODEL_CONVERT_GUIDE.md 第二节"
  exit 1
fi

echo "=== MindSpore Lite 转换 ==="
# UltraFace 输入 NCHW: 1x3x240x320（高x宽）
"$CONVERTER_LITE" \
  --fmk=ONNX \
  --modelFile="$ONNX" \
  --outputFile="$OUT_MS" \
  --inputShape="input:1,3,240,320" \
  --inputDataFormat=NCHW \
  --outputDataFormat=NHWC

MS_FILE="${OUT_MS}.ms"
if [[ ! -f "$MS_FILE" ]]; then
  echo "转换失败，未生成 ${MS_FILE}"
  exit 1
fi

mkdir -p "$APP_MODEL_DIR"
cp "$MS_FILE" "${APP_MODEL_DIR}/mtcnn.om"
echo "已复制 → ${APP_MODEL_DIR}/mtcnn.om"
echo "请在 DevEco 中 Rebuild，真机 HiLog 过滤: OmModelLoader|MindSporeModelRunner"
