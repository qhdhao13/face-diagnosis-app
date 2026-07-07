"""
古籍风标注渲染：色部方格 + 竖排名称（自适应字号）+ 68 关键点
"""
from __future__ import annotations

from pathlib import Path
from typing import List, Tuple

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from region_mapper import RegionRect

# 25 区区分色（BGR）
PALETTE: List[Tuple[int, int, int]] = [
    (60, 60, 200), (60, 180, 60), (200, 120, 40), (180, 60, 180), (40, 160, 160),
    (80, 80, 220), (80, 200, 80), (220, 140, 60), (200, 80, 200), (60, 180, 180),
    (100, 100, 240), (100, 220, 100), (240, 160, 80), (220, 100, 220), (80, 200, 200),
    (120, 120, 255), (120, 240, 120), (255, 180, 100), (240, 120, 240), (100, 220, 220),
    (140, 140, 255), (140, 255, 140), (255, 200, 120), (255, 140, 255), (120, 240, 240),
]


def _load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Light.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
        "C:/Windows/Fonts/msyh.ttc",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def _cell_pixel_size(r: RegionRect) -> Tuple[int, int]:
    """估算格子像素宽高（用于字号适配）"""
    if r.quad and len(r.quad) == 4:
        ys = [p[1] for p in r.quad]
        xs = [p[0] for p in r.quad]
        return int(max(xs) - min(xs)), int(max(ys) - min(ys))
    return r.w, r.h


def _fit_font_size(name: str, cell_w: int, cell_h: int, max_font: int = 8) -> int:
    """竖排文字需 fit 格高与格宽；优先保证完整显示"""
    min_font = 5
    for fs in range(max_font, min_font - 1, -1):
        need_h = len(name) * (fs + 1) + 6
        need_w = fs + 6
        if need_h <= cell_h and need_w <= cell_w:
            return fs
    return min_font


def _label_position(
    r: RegionRect,
    font_size: int,
    inset: int,
) -> Tuple[int, int]:
    """竖排名称居中于格内，避免贴边被裁切"""
    cell_w, cell_h = _cell_pixel_size(r)
    text_h = len(r.name) * (font_size + 1)
    if r.quad and len(r.quad) == 4:
        x0 = int(min(p[0] for p in r.quad))
        y0 = int(min(p[1] for p in r.quad))
    else:
        x0, y0 = r.x, r.y
    lx = x0 + max(inset, (cell_w - font_size) // 2)
    ly = y0 + max(inset, (cell_h - text_h) // 2)
    return lx, ly


def draw_vertical_text(
    img_bgr: np.ndarray,
    text: str,
    x: int,
    y: int,
    font_size: int = 14,
    color=(255, 255, 0),
) -> np.ndarray:
    """竖排文字：亮黄色 + 细黑描边，提高可读性"""
    pil = Image.fromarray(cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(pil)
    font = _load_font(font_size)
    cy = y
    for ch in text:
        # 描边
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            draw.text((x + dx, cy + dy), ch, font=font, fill=(0, 0, 0))
        draw.text((x, cy), ch, font=font, fill=color)
        cy += font_size + 1
    return cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)


def render_annotated(
    image_bgr: np.ndarray,
    regions: List[RegionRect],
    line_width: int = 2,
    font_size: int = 0,
    label_inset: int = 2,
    max_font: int = 10,
) -> np.ndarray:
    """叠加 25 色部方格；font_size=0 时按格大小自动缩小字号"""
    out = image_bgr.copy()
    for i, r in enumerate(regions):
        color = PALETTE[i % len(PALETTE)]
        cell_w, cell_h = _cell_pixel_size(r)
        fs = font_size if font_size > 0 else _fit_font_size(r.name, cell_w, cell_h, max_font=max_font)

        if r.quad and len(r.quad) == 4:
            pts = np.array([[int(p[0]), int(p[1])] for p in r.quad], dtype=np.int32)
            cv2.polylines(out, [pts], isClosed=True, color=color, thickness=line_width)
        else:
            cv2.rectangle(out, (r.x, r.y), (r.x + r.w, r.y + r.h), color, line_width)

        lx, ly = _label_position(r, fs, label_inset)
        out = draw_vertical_text(out, r.name, lx, ly, font_size=fs, color=(255, 255, 0))

    return out


def draw_landmarks_68(
    image_bgr: np.ndarray,
    points_68: np.ndarray,
    radius: int = 1,
    color: Tuple[int, int, int] = (0, 0, 0),
) -> np.ndarray:
    """绘制 68 个黑色关键点（默认半径 1 ≈ 原 3 的 30%）"""
    out = image_bgr.copy()
    for i in range(len(points_68)):
        x = int(round(points_68[i][0]))
        y = int(round(points_68[i][1]))
        cv2.circle(out, (x, y), max(1, radius), color, thickness=-1, lineType=cv2.LINE_AA)
    return out


def save_image(path: Path, image_bgr: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), image_bgr)
