"""
二十五色部完整分析流水线（供 demo / 云端 API 共用）
"""
from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import cv2
import numpy as np

from color_analysis import analyze_all_regions
from grid_from_68 import compute_grid_bounds_from_68
from landmark_provider import detect_from_bytes, extract_68_points
from region_mapper import (
    clamp_regions,
    compute_baseline,
    load_regions_config,
    map_regions,
    regions_to_dict,
)
from gender_estimate import check_profile_gender, estimate_gender_from_68
from renderer import draw_landmarks_68, render_annotated, save_image
from report_builder import build_color_report


def _decode_image(image_bytes: bytes) -> np.ndarray:
    """字节 → BGR 图像"""
    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("无法解码图片")
    return img


def run_pipeline_from_bytes(
    image_bytes: bytes,
    session_dir: Path,
    phone: str = "",
    profile_gender: str = "",
    config_path: Optional[Path] = None,
    engine: str = "auto",
) -> Dict[str, Any]:
    """
    执行：68点 → 25区 → 标注图 → Lab色诊 → 落盘
    session_dir 下保存全部数据与图片
    """
    root = Path(__file__).parent
    cfg_path = config_path or (root / "regions_25.json")
    config = load_regions_config(cfg_path)

    session_dir.mkdir(parents=True, exist_ok=True)
    original_path = session_dir / "original.jpg"
    original_path.write_bytes(image_bytes)

    landmarks = detect_from_bytes(image_bytes, prefer=engine)
    points_68 = extract_68_points(landmarks)

    # 性别估计：与用户设置对比（辅助校验，非身份证明）
    gender_detected = estimate_gender_from_68(points_68)
    gender_check = check_profile_gender(profile_gender, gender_detected)

    img = _decode_image(image_bytes)
    h, w = img.shape[:2]
    L, u, v, origin = compute_baseline(landmarks)

    row_bounds = None
    col_bounds = None
    if config.get("grid", {}).get("dynamic_from_68", False):
        row_bounds, col_bounds = compute_grid_bounds_from_68(points_68, origin, u, v, L)

    regions = clamp_regions(map_regions(landmarks, config, w, h, pts68=points_68), w, h)

    annotated = render_annotated(img, regions, line_width=2, font_size=0)
    annotated = draw_landmarks_68(annotated, points_68, radius=1)
    annotated_path = session_dir / "annotated.jpg"
    save_image(annotated_path, annotated)

    regions_payload = regions_to_dict(
        regions,
        L,
        layout=config.get("layout", "grid_nine_rows"),
        row_bounds=row_bounds,
        col_bounds=col_bounds,
    )
    regions_payload["engine"] = landmarks.engine
    regions_payload["shangen"] = list(landmarks.shangen)
    regions_payload["zhuntou"] = list(landmarks.zhuntou)
    regions_path = session_dir / "regions_pixel.json"
    regions_path.write_text(json.dumps(regions_payload, ensure_ascii=False, indent=2), encoding="utf-8")

    lm_path = session_dir / "landmarks_68.json"
    lm_path.write_text(
        json.dumps(
            {"engine": landmarks.engine, "count": 68, "points": [[float(p[0]), float(p[1])] for p in points_68]},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    color_results = analyze_all_regions(img, regions)
    color_report = build_color_report(
        color_results,
        image_path=str(original_path),
        engine=landmarks.engine,
    )
    color_path = session_dir / "color_report.json"
    color_path.write_text(json.dumps(color_report, ensure_ascii=False, indent=2), encoding="utf-8")

    meta = {
        "phone": phone,
        "createdAt": int(time.time() * 1000),
        "engine": landmarks.engine,
        "zhongting_L": L,
        "imageWidth": w,
        "imageHeight": h,
        "regionCount": 25,
        "profileGender": profile_gender,
        "detectedGender": gender_detected.get("gender", "未知"),
        "genderConfidence": gender_detected.get("confidence", 0.0),
        "genderMismatch": gender_check.get("mismatch", False),
        "genderWarning": gender_check.get("warning", ""),
    }
    meta_path = session_dir / "meta.json"
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")

    return {
        "meta": meta,
        "genderCheck": gender_check,
        "colorReport": color_report,
        "regionsPixel": regions_payload,
        "files": {
            "original": "original.jpg",
            "annotated": "annotated.jpg",
            "colorReport": "color_report.json",
            "regionsPixel": "regions_pixel.json",
            "landmarks": "landmarks_68.json",
            "meta": "meta.json",
        },
    }
