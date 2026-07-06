#!/usr/bin/env bash
# 在 Linux Docker 容器内运行 MindSpore Lite converter_lite，将 ONNX 转为 .ms
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ONNX_DIR="$SCRIPT_DIR/output/onnx"
OUT_DIR="$SCRIPT_DIR/output/ms"
RAWFILE_DIR="$PROJECT_ROOT/entry/src/main/resources/rawfile/models"
MSLITE_VER="2.3.0"
MSLITE_TAR="mindspore-lite-${MSLITE_VER}-linux-x64.tar.gz"
MSLITE_URL="https://msrelease.obs.cn-north-4.myhuaweicloud.com/${MSLITE_VER}/MindSpore/lite/release/linux/x86_64/cloud_fusion/${MSLITE_TAR}"

mkdir -p "$ONNX_DIR" "$OUT_DIR"

# 若本地尚无 ONNX，复制 UltraFace
if [[ ! -f "$ONNX_DIR/mtcnn_ultraface.onnx" ]]; then
  cp "$SCRIPT_DIR/output/version-RFB-320.onnx" "$ONNX_DIR/mtcnn_ultraface.onnx"
fi

echo "=== Docker 内下载 MindSpore Lite ${MSLITE_VER} 并转换 ==="
docker run --rm \
  -v "$SCRIPT_DIR/output:/work" \
  -v "$OUT_DIR:/out" \
  ubuntu:22.04 bash -lc "
    set -e
    apt-get update -qq && apt-get install -y -qq wget ca-certificates libgomp1 > /dev/null
    cd /tmp
    wget -q --timeout=120 '${MSLITE_URL}' -O ${MSLITE_TAR} || wget -q --timeout=120 'https://ghproxy.net/https://github.com/mindspore-ai/mindspore-lite/releases/download/v${MSLITE_VER}/${MSLITE_TAR}' -O ${MSLITE_TAR}
    tar xzf ${MSLITE_TAR}
    PKG=\$(ls -d mindspore-lite-*-linux-x64 | head -1)
    CONVERTER=\$PKG/tools/converter/converter/converter_lite
    LIBDIR=\$PKG/tools/converter/lib
    export LD_LIBRARY_PATH=\$LIBDIR:\$LD_LIBRARY_PATH
    chmod +x \$CONVERTER
    \$CONVERTER --help | head -3
    \$CONVERTER \
      --fmk=ONNX \
      --modelFile=/work/onnx/mtcnn_ultraface.onnx \
      --outputFile=/out/mtcnn \
      --inputShape=\"input:1,3,240,320\" \
      --inputDataFormat=NCHW \
      --outputDataFormat=NHWC
    ls -la /out/
  "

if [[ -f "$OUT_DIR/mtcnn.ms" ]]; then
  mkdir -p "$RAWFILE_DIR"
  cp "$OUT_DIR/mtcnn.ms" "$RAWFILE_DIR/mtcnn.om"
  echo "已部署 → $RAWFILE_DIR/mtcnn.om ($(du -h "$RAWFILE_DIR/mtcnn.om" | cut -f1))"
else
  echo "转换失败，未生成 mtcnn.ms"
  exit 1
fi
