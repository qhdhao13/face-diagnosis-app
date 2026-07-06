#!/usr/bin/env bash
# 将 ONNX 转为 App rawfile/*.om（需 Linux/Windows 上的 converter_lite）
# 用法: CONVERTER_LITE=/path/to/converter_lite bash prepare_rawfile.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ONNX_DIR="$SCRIPT_DIR/output/onnx"
RAWFILE="$PROJECT_ROOT/entry/src/main/resources/rawfile/models"
CONVERTER="${CONVERTER_LITE:-}"

if [[ -z "$CONVERTER" || ! -x "$CONVERTER" ]]; then
  echo "请设置可执行的 converter_lite 路径，例如："
  echo "  export CONVERTER_LITE=/path/to/mindspore-lite-2.3.0-linux-x64/tools/converter/converter/converter_lite"
  echo "  bash prepare_rawfile.sh"
  echo ""
  echo "Mac 用户：在 DevEco Studio（Windows）或 Linux 虚拟机中运行；或 bash convert_in_docker.sh（需 Docker 可用）"
  exit 1
fi

LIBDIR="$(dirname "$CONVERTER")/../lib"
export LD_LIBRARY_PATH="${LIBDIR}:${LD_LIBRARY_PATH:-}"

mkdir -p "$RAWFILE" "$SCRIPT_DIR/output/ms"

convert_one() {
  local name="$1" onnx="$2" shape="$3" fmt="$4"
  echo "=== 转换 $name ==="
  "$CONVERTER" --fmk=ONNX --modelFile="$onnx" --outputFile="$SCRIPT_DIR/output/ms/$name" \
    --inputShape="$shape" --inputDataFormat="$fmt" --outputDataFormat=NHWC
  cp "$SCRIPT_DIR/output/ms/${name}.ms" "$RAWFILE/${name}.om"
  echo "  → $RAWFILE/${name}.om"
}

convert_one "mtcnn" "$ONNX_DIR/mtcnn_ultraface.onnx" "input:1,3,240,320" "NCHW"
convert_one "mobilenetv3" "$ONNX_DIR/mobilenetv3_small_224.onnx" "input:1,3,224,224" "NCHW"
if [[ -f "$ONNX_DIR/mobileclip_s1_image.onnx" ]]; then
  convert_one "mobileclip" "$ONNX_DIR/mobileclip_s1_image.onnx" "input:1,3,224,224" "NCHW"
else
  echo "跳过 mobileclip（需先导出 output/onnx/mobileclip_s1_image.onnx）"
fi

echo "完成。请在 DevEco Rebuild 并真机验证。"
