#!/usr/bin/env python3
"""
二十五明堂色部标注 Demo
每张图：检测 68 点 → 动态划分 25 色部 → 叠加标注
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import cv2

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT))

from grid_from_68 import compute_grid_bounds_from_68
from landmark_provider import detect, extract_68_points
from region_mapper import (
    clamp_regions,
    compute_baseline,
    load_regions_config,
    map_regions,
    regions_to_dict,
)
from renderer import draw_landmarks_68, render_annotated, save_image
from validate import validate_config


def main() -> int:
    parser = argparse.ArgumentParser(description="古籍25色部标注（68点驱动）")
    parser.add_argument("--image", "-i", type=Path, help="输入人脸照片")
    parser.add_argument("--engine", choices=["auto", "mediapipe", "dlib"], default="auto")
    parser.add_argument("--config", type=Path, default=ROOT / "regions_25.json")
    parser.add_argument("--out-dir", type=Path, default=ROOT / "output")
    parser.add_argument("--line-width", type=int, default=2)
    parser.add_argument("--font-size", type=int, default=0, help="0=按格自动缩小")
    parser.add_argument("--landmark-radius", type=int, default=1, help="68点半径(默认1，约为原30%%)")
    parser.add_argument("--no-landmarks", action="store_true")
    parser.add_argument(
        "--analyze-color",
        action="store_true",
        help="对25色部逐区Lab色诊分析，输出 color_report.json",
    )
    args = parser.parse_args()

    ok, errs = validate_config(args.config)
    if not ok:
        print("[FAIL] regions_25.json 校验未通过:")
        for e in errs:
            print(" ", e)
        return 1
    print("[OK] regions_25.json 校验通过")

    if args.image is None:
        print("未指定 --image。用法: python demo.py --image 照片路径")
        return 0

    if not args.image.exists():
        print(f"图片不存在: {args.image}")
        return 1

    config = load_regions_config(args.config)
    landmarks = detect(args.image, prefer=args.engine)
    points_68 = extract_68_points(landmarks)
    print(f"[OK] 关键点: {landmarks.engine}, 68点已提取")

    img = cv2.imread(str(args.image))
    h, w = img.shape[:2]
    L, u, v, origin = compute_baseline(landmarks)

    row_bounds = None
    col_bounds = None
    if config.get("grid", {}).get("dynamic_from_68", False):
        row_bounds, col_bounds = compute_grid_bounds_from_68(points_68, origin, u, v, L)

    regions = map_regions(landmarks, config, w, h, pts68=points_68)
    regions = clamp_regions(regions, w, h)

    annotated = render_annotated(
        img,
        regions,
        line_width=args.line_width,
        font_size=args.font_size,
    )
    if not args.no_landmarks:
        annotated = draw_landmarks_68(annotated, points_68, radius=args.landmark_radius)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    out_img = args.out_dir / "annotated.jpg"
    out_json = args.out_dir / "regions_pixel.json"
    out_lm = args.out_dir / "landmarks_68.json"
    save_image(out_img, annotated)

    payload = regions_to_dict(
        regions,
        L,
        layout=config.get("layout", "grid_nine_rows"),
        row_bounds=row_bounds,
        col_bounds=col_bounds,
    )
    payload["engine"] = landmarks.engine
    payload["shangen"] = list(landmarks.shangen)
    payload["zhuntou"] = list(landmarks.zhuntou)
    out_json.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    out_lm.write_text(
        json.dumps(
            {"engine": landmarks.engine, "count": 68, "points": [[float(p[0]), float(p[1])] for p in points_68]},
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    print(f"[OK] 标注图: {out_img}")
    print(f"[OK] 68点坐标: {out_lm}")
    print(f"[OK] 25色部: {out_json}")
    print(f"     中庭 L={L:.2f}px, 动态格线={'是' if row_bounds else '否'}")

    if args.analyze_color:
        from color_analysis import analyze_all_regions
        from report_builder import build_color_report

        color_results = analyze_all_regions(img, regions)
        report = build_color_report(
            color_results,
            image_path=str(args.image),
            engine=landmarks.engine,
        )
        out_color = args.out_dir / "color_report.json"
        out_color.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"[OK] 色诊报告: {out_color}")
        print(f"     综合: {report['summary']['summary_text'][:80]}...")
        print("     --- 25区分项（前5条）---")
        for line in report["line_items"][:5]:
            print(f"       {line}")
        print("       ...")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
