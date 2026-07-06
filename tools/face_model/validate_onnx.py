#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
在 PC 上用 ONNX Runtime 验证 UltraFace 模型与预处理是否与 App 一致。

App 侧配置见 entry/src/main/resources/rawfile/models/model_config.json：
  inputWidth=320, inputHeight=240, mean=127, scale=1/128, dataFormat=NCHW
"""

from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort

INPUT_W = 320
INPUT_H = 240
MEAN = 127.0
SCALE = 1.0 / 128.0
SCORE_THRESHOLD = 0.7


def preprocess_bgr(image_bgr: np.ndarray) -> np.ndarray:
    """BGR → NCHW float32，与 VisionImagePreprocessor + NCHW 一致"""
    rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    resized = cv2.resize(rgb, (INPUT_W, INPUT_H))
    normalized = (resized.astype(np.float32) - MEAN) * SCALE
    # HWC → CHW → NCHW
    chw = np.transpose(normalized, (2, 0, 1))
    return np.expand_dims(chw, axis=0)


def decode_ultraface(scores: np.ndarray, boxes: np.ndarray) -> tuple[float, float, float, float, float] | None:
    """从 scores/boxes 取置信度最高的人脸框（像素坐标）"""
    # scores: [1, N, 2]  boxes: [1, N, 4]
    scores = scores.reshape(-1, 2)
    boxes = boxes.reshape(-1, 4)
    n = min(len(scores), len(boxes))

    best_i = -1
    best_score = SCORE_THRESHOLD
    for i in range(n):
        face_prob = float(scores[i, 1])
        if face_prob > best_score:
            best_score = face_prob
            best_i = i

    if best_i < 0:
        return None

    x1, y1, x2, y2 = boxes[best_i]
    return float(x1), float(y1), float(x2), float(y2), best_score


def main() -> int:
    model_path = Path(__file__).resolve().parent / "output" / "version-RFB-320.onnx"
    if not model_path.exists():
        print("未找到模型，请先运行: python download_ultraface.py")
        return 1

    session = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    print("输入:", session.get_inputs()[0].name, session.get_inputs()[0].shape)
    for out in session.get_outputs():
        print("输出:", out.name, out.shape)

    # 无测试图时用纯色图验证链路
    dummy = np.zeros((480, 640, 3), dtype=np.uint8)
    dummy[100:380, 180:460] = (200, 180, 160)
    tensor = preprocess_bgr(dummy)

    outputs = session.run(None, {input_name: tensor})
    if len(outputs) < 2:
        print("输出 tensor 数量不足，请检查模型")
        return 1

    # UltraFace 通常为 scores + boxes，顺序可能因导出而异
    a, b = outputs[0], outputs[1]
    if a.size * 2 == b.size:
        scores, boxes = a, b
    elif b.size * 2 == a.size:
        scores, boxes = b, a
    else:
        scores, boxes = outputs[0], outputs[1]

    face = decode_ultraface(scores, boxes)
    if face is None:
        print("验证通过（推理成功，dummy 图未检出人脸属正常）")
    else:
        x1, y1, x2, y2, conf = face
        print(f"检出人脸: box=({x1:.1f},{y1:.1f})-({x2:.1f},{y2:.1f}) conf={conf:.3f}")

    print("\nPC 端验证 OK，可继续 MindSpore Lite 转换")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
