#!/usr/bin/env python3
"""
25 区格线视觉/解剖校验
1. 基于 68 点与 bbox 的几何验收（必跑，本地视觉校验）
2. 可选：若设置 ARK_API_KEY / OPENAI_API_KEY，调用云端视觉大模型
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Tuple

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))

import numpy as np

from grid_from_68 import _estimate_hairline_v, _pt_uv
from landmark_provider import detect, extract_68_points
from region_mapper import compute_baseline


def _region_by_name(regions: List[dict], name: str) -> dict:
    for r in regions:
        if r["name"] == name:
            return r
    raise KeyError(name)


def _y_in_bbox(y: float, bbox: List[int]) -> bool:
    _, by, _, h = bbox
    return by <= y <= by + h


def _center_y(bbox: List[int]) -> float:
    _, y, _, h = bbox
    return y + h / 2.0


def geometric_validate(
    regions_pixel: dict,
    pts68: np.ndarray,
    origin: Tuple[float, float],
    u: np.ndarray,
    v: np.ndarray,
    L: float,
) -> Tuple[bool, List[str], Dict[str, Any]]:
    """用 68 点验收上/中/下庭关键色部位置"""
    notes: List[str] = []
    metrics: Dict[str, Any] = {}
    ok = True

    def py(i: int) -> float:
        return float(pts68[i][1])

    brow_inner_y = (py(19) + py(24)) / 2.0
    nasal_root_y = py(27)
    eye_upper_y = min(py(37), py(38), py(43), py(44))
    nose_tip_y = py(33)
    nose_base_y = py(30)
    upper_lip_y = py(51)
    lower_lip_y = py(57)

    tianting = _region_by_name(regions_pixel["regions"], "天庭")
    que = _region_by_name(regions_pixel["regions"], "阙中")
    shangen = _region_by_name(regions_pixel["regions"], "山根")
    zhun = _region_by_name(regions_pixel["regions"], "准头")
    ren = _region_by_name(regions_pixel["regions"], "人中")
    shou = _region_by_name(regions_pixel["regions"], "寿上")

    ty = _center_y(tianting["bbox"])
    qy = _center_y(que["bbox"])
    sy = _center_y(shangen["bbox"])
    zy = _center_y(zhun["bbox"])
    ry = _center_y(ren["bbox"])

    v_hair = _estimate_hairline_v(pts68, origin, u, v, L)
    hair_y_approx = origin[1] + v_hair * L * float(v[1])
    tianting_top = tianting["bbox"][1]

    metrics["centers_y"] = {
        "天庭": ty, "阙中": qy, "山根": sy, "准头": zy, "人中": ry,
    }
    metrics["landmarks_y"] = {
        "发际估算": hair_y_approx,
        "眉内侧": brow_inner_y,
        "鼻根": nasal_root_y,
        "鼻尖": nose_tip_y,
        "鼻下": nose_base_y,
        "上唇": upper_lip_y,
        "下唇": lower_lip_y,
    }

    # --- 上庭 ---
    if ty < qy < sy:
        notes.append("PASS 纵向顺序：天庭→阙中→山根")
    else:
        ok = False
        notes.append(f"FAIL 纵向顺序：天庭({ty:.0f}) 阙中({qy:.0f}) 山根({sy:.0f})")

    que_bottom = que["bbox"][1] + que["bbox"][3]
    if que_bottom <= brow_inner_y + 2:
        notes.append(f"PASS 阙中下缘({que_bottom:.0f}) 未压眉线")
    else:
        ok = False
        notes.append(f"FAIL 阙中下缘({que_bottom:.0f}) 压入眉区")

    if _y_in_bbox(nasal_root_y, shangen["bbox"]):
        notes.append(f"PASS 山根覆盖鼻根 y={nasal_root_y:.0f}")
    else:
        ok = False
        notes.append(f"FAIL 山根未覆盖鼻根 y={nasal_root_y:.0f}")

    if tianting_top <= hair_y_approx + 12:
        notes.append(f"PASS 天庭上缘({tianting_top:.0f}) 贴近发际估算({hair_y_approx:.0f})")
    else:
        ok = False
        notes.append(
            f"FAIL 天庭上缘({tianting_top:.0f}) 距发际({hair_y_approx:.0f}) 仍偏远"
        )

    # --- 中庭：准头 / 寿上 ---
    if abs(zy - nose_tip_y) <= 14:
        notes.append(f"PASS 准头中心({zy:.0f}) 贴近鼻尖({nose_tip_y:.0f})")
    else:
        ok = False
        notes.append(f"FAIL 准头中心({zy:.0f}) 偏离鼻尖({nose_tip_y:.0f})")

    zhun_h = zhun["bbox"][3]
    if zhun_h >= 20:
        notes.append(f"PASS 准头格高 {zhun_h}px，寿上与人中之间可辨")
    else:
        ok = False
        notes.append(f"FAIL 准头格高仅 {zhun_h}px，标签被挤压")

    zhun_bottom = zhun["bbox"][1] + zhun["bbox"][3]
    if zhun_bottom <= upper_lip_y + 4:
        notes.append(f"PASS 准头下缘({zhun_bottom:.0f}) 未占人中沟(上唇 y={upper_lip_y:.0f})")
    else:
        ok = False
        notes.append(f"FAIL 准头下缘({zhun_bottom:.0f}) 下探占用人中区")

    shou_bottom = shou["bbox"][1] + shou["bbox"][3]
    if shou_bottom < zhun["bbox"][1] + 2:
        notes.append(f"PASS 寿上({shou['name']}) 在准头之上，标签区 y={shou['bbox'][1]}-{shou_bottom:.0f}")
    else:
        notes.append(f"INFO 寿上格 y={shou['bbox'][1]}-{shou_bottom:.0f}（年上/寿上=鼻柱中段）")

    # --- 下庭：人中 ---
    philtrum_mid = (nose_tip_y + upper_lip_y) / 2.0
    if abs(ry - philtrum_mid) <= 16:
        notes.append(f"PASS 人中中心({ry:.0f}) 在人中沟({philtrum_mid:.0f})")
    else:
        ok = False
        notes.append(f"FAIL 人中中心({ry:.0f}) 偏离人中沟({philtrum_mid:.0f})")

    if not _y_in_bbox(lower_lip_y, ren["bbox"]):
        notes.append(f"PASS 人中未覆盖下唇 y={lower_lip_y:.0f}")
    else:
        ok = False
        notes.append(f"FAIL 人中格覆盖下唇 y={lower_lip_y:.0f}")

    ren_bottom = ren["bbox"][1] + ren["bbox"][3]
    if ren_bottom <= upper_lip_y + 10:
        notes.append(f"PASS 人中下缘({ren_bottom:.0f}) 在上唇附近，不在下唇")
    else:
        ok = False
        notes.append(f"FAIL 人中下缘({ren_bottom:.0f}) 过低（上唇 y={upper_lip_y:.0f}）")

    return ok, notes, metrics


def _encode_image_b64(path: Path) -> str:
    return base64.standard_b64encode(path.read_bytes()).decode("ascii")


def llm_visual_validate(image_path: Path, model: str = "doubao-vision") -> Tuple[bool, str]:
    models_file = Path.home() / ".claude/skills/video-analyzer/scripts/models.json"
    if not models_file.exists():
        return False, "SKIP 未找到 video-analyzer models.json"

    cfg = json.loads(models_file.read_text())
    mcfg = cfg["models"].get(model) or cfg["models"][cfg["default_model"]]
    api_key = os.environ.get(mcfg["api_key_env"], "")
    if not api_key:
        return False, f"SKIP 未设置 {mcfg['api_key_env']}"

    try:
        from openai import OpenAI
    except ImportError:
        return False, "SKIP 未安装 openai 包"

    prompt = (
        "面诊25区标注图。请检查：1)天庭上缘是否近发际 2)准头是否在鼻尖 "
        "3)人中是否在人中沟而非下唇 4)文字是否为亮黄色。"
        "JSON: {\"pass\":bool,\"issues\":[]}"
    )
    client = OpenAI(base_url=mcfg["base_url"], api_key=api_key)
    b64 = _encode_image_b64(image_path)
    resp = client.chat.completions.create(
        model=mcfg["model"],
        messages=[{
            "role": "user",
            "content": [
                {"type": "text", "text": prompt},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
            ],
        }],
        max_tokens=500,
    )
    text = resp.choices[0].message.content or ""
    passed = '"pass":true' in text.replace(" ", "").lower()
    return passed, text


def main() -> int:
    parser = argparse.ArgumentParser(description="25区格线几何+视觉校验")
    parser.add_argument("--image", type=Path, default=ROOT / "assets" / "test_face.png")
    parser.add_argument("--regions-json", type=Path, default=ROOT / "output" / "regions_pixel.json")
    parser.add_argument("--annotated", type=Path, default=ROOT / "output" / "annotated.jpg")
    parser.add_argument("--llm", action="store_true")
    args = parser.parse_args()

    if not args.regions_json.exists():
        print(f"[FAIL] 缺少 {args.regions_json}，请先运行 demo.py")
        return 1

    regions_pixel = json.loads(args.regions_json.read_text(encoding="utf-8"))
    landmarks = detect(args.image)
    pts68 = extract_68_points(landmarks)
    L, u, v, origin = compute_baseline(landmarks)

    ok, notes, metrics = geometric_validate(regions_pixel, pts68, origin, u, v, L)
    print("=== 本地几何校验（68点 + 视觉规则） ===")
    for n in notes:
        print(n)
    print("metrics:", json.dumps(metrics, ensure_ascii=False, indent=2))

    if args.llm and args.annotated.exists():
        print("\n=== 云端视觉大模型 ===")
        llm_ok, llm_text = llm_visual_validate(args.annotated)
        print(llm_text)
        ok = ok and llm_ok

    print("\n" + ("[PASS] 格线验收通过" if ok else "[FAIL] 格线需继续调整"))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
