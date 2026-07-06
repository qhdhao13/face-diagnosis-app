#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
从魔搭 / HuggingFace 下载项目三端侧模型原始权重到 tools/face_model/output/downloads/

已验证可用的魔搭 Model ID：
  - iic/cv_manual_face-detection_mtcnn        MTCNN numpy 权重（需另转 ONNX，Stage1 建议用 UltraFace）
  - apple/MobileCLIP-S0                       MobileCLIP 权重 .pt
  - damo/cv_resnet101_image-multiple-human-parsing  人体解析（体积大 ~723MB，不适合直接进 App）
"""

from __future__ import annotations

import os
import urllib.request
from pathlib import Path

from modelscope.hub.snapshot_download import snapshot_download

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "output"
DOWNLOADS = OUT / "downloads"

MODELSCOPE_MODELS = [
    ("apple/MobileCLIP-S0", "Stage3 MobileCLIP"),
    ("iic/cv_manual_face-detection_mtcnn", "Stage1 MTCNN 参考权重"),
]

ULTRAFACE_URL = (
    "https://ghproxy.net/https://github.com/onnx/models/raw/main/"
    "validated/vision/body_analysis/ultraface/models/version-RFB-320.onnx"
)


def download_ultraface() -> Path:
    OUT.mkdir(parents=True, exist_ok=True)
    target = OUT / "version-RFB-320.onnx"
    if target.exists() and target.stat().st_size > 100_000:
        print(f"UltraFace 已存在: {target}")
        return target
    print("下载 UltraFace ONNX（Stage1 推荐）…")
    urllib.request.urlretrieve(ULTRAFACE_URL, target)
    print(f"  → {target} ({target.stat().st_size // 1024} KB)")
    return target


def download_modelscope() -> None:
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    for model_id, desc in MODELSCOPE_MODELS:
        print(f"\n魔搭下载 [{desc}]: {model_id}")
        try:
            path = snapshot_download(model_id, cache_dir=str(DOWNLOADS))
            print(f"  OK → {path}")
        except Exception as err:
            print(f"  FAIL: {err}")


def main() -> int:
    onnx_dir = OUT / "onnx"
    onnx_dir.mkdir(parents=True, exist_ok=True)
    ultra = download_ultraface()
    # 供 converter 使用
    link = onnx_dir / "mtcnn_ultraface.onnx"
    if not link.exists():
        import shutil
        shutil.copy2(ultra, link)
    download_modelscope()
    print("\n完成。下一步: bash convert_in_docker.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
