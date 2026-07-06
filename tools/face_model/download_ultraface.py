#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
下载 UltraFace ONNX（推荐作为 Stage1 人脸检测，文件名仍用 mtcnn.om 放入 App）

为什么用 UltraFace 而不是完整 MTCNN：
- MTCNN 是三阶段级联（P/R/O-Net），端侧推理与转换都更复杂
- UltraFace 单模型、320x240、约 1.2MB，与 model_config.json 已对齐
"""

from __future__ import annotations

import sys
import urllib.request
from pathlib import Path

# ONNX Model Zoo 官方 UltraFace RFB-320
ULTRAFACE_URL = (
    "https://github.com/onnx/models/raw/main/"
    "validated/vision/body_analysis/ultraface/models/version-RFB-320.onnx"
)

OUTPUT_NAME = "version-RFB-320.onnx"


def main() -> int:
    out_dir = Path(__file__).resolve().parent / "output"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / OUTPUT_NAME

    print(f"正在下载 UltraFace ONNX …")
    print(f"  来源: {ULTRAFACE_URL}")
    urllib.request.urlretrieve(ULTRAFACE_URL, out_path)
    size_kb = out_path.stat().st_size / 1024
    print(f"已保存: {out_path} ({size_kb:.1f} KB)")
    print()
    print("下一步:")
    print("  1. python validate_onnx.py")
    print("  2. 按 docs/MODEL_CONVERT_GUIDE.md 转为 .ms 并重命名为 mtcnn.om")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
