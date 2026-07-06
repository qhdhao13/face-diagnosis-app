"""
二十五明堂色部映射（v2 网格化）
九行三列相邻方格，格线以中庭 L 与 u/v 局部坐标定义，格间不重叠
"""
from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np

from landmark_provider import FaceLandmarks
from grid_from_68 import compute_grid_bounds_from_68

Point = Tuple[float, float]


@dataclass
class RegionRect:
    """单色部像素四边形格 + 轴对齐包围框（供裁剪/统计）"""
    id: int
    name: str
    side: str
    x: int
    y: int
    w: int
    h: int
    center: Point
    size_L: Tuple[float, float]
    quad: List[Point]
    grid_row: int = -1
    grid_col: int = -1


def load_regions_config(config_path: Path) -> dict:
    return json.loads(config_path.read_text(encoding="utf-8"))


def compute_baseline(landmarks: FaceLandmarks) -> Tuple[float, np.ndarray, np.ndarray, Point]:
    """
    计算中庭 L 与局部坐标系
    v: 山根→准头 单位向量（向下鼻方向）
    u: 被摄者右侧单位法向
    """
    sx, sy = landmarks.shangen
    zx, zy = landmarks.zhuntou
    vx, vy = zx - sx, zy - sy
    L = math.hypot(vx, vy)
    if L < 1e-3:
        L = 1.0
        vx, vy = 0.0, 1.0
    v = np.array([vx / L, vy / L])
    u = np.array([v[1], -v[0]])
    return L, u, v, landmarks.shangen


def estimate_face_half_width_L(landmarks: FaceLandmarks, u: np.ndarray, origin: Point, L: float) -> float:
    """沿 u 轴估计半脸宽（L 倍数），用于自适应列宽"""
    ox, oy = origin
    max_proj = 0.0
    for px, py in landmarks.points:
        du = (px - ox) * u[0] + (py - oy) * u[1]
        max_proj = max(max_proj, abs(du))
    return max_proj / L if L > 0 else 1.0


def _resolve_col_bounds(grid: dict, half_width_L: float) -> List[float]:
    """列边界；可选按实际脸宽缩放外缘"""
    bounds = list(grid["col_bounds_L"])
    if not grid.get("face_width_scale", False):
        return bounds
    w_min = grid.get("face_width_min_L", bounds[-1])
    w_max = grid.get("face_width_max_L", bounds[-1])
    outer = max(w_min, min(w_max, half_width_L))
    bounds[0] = -outer
    bounds[-1] = outer
    return bounds


def _cell_uv_rect(
    row: int,
    col: int,
    row_bounds: List[float],
    col_bounds: List[float],
) -> Tuple[float, float, float, float]:
    """格单元在 (u,v) 空间中的范围，单位：L 倍数"""
    u0 = col_bounds[col]
    u1 = col_bounds[col + 1]
    v0 = row_bounds[row]
    v1 = row_bounds[row + 1]
    return u0, v0, u1, v1


def _uv_rect_to_pixels(
    u0: float,
    v0: float,
    u1: float,
    v1: float,
    origin: Point,
    u: np.ndarray,
    v: np.ndarray,
    L: float,
    img_w: int,
    img_h: int,
) -> Tuple[int, int, int, int, Point, List[Point]]:
    """UV 矩形 → 像素四边形 + 轴对齐包围框"""
    ox, oy = origin
    corners: List[Point] = []
    for uc, vc in ((u0, v0), (u1, v0), (u1, v1), (u0, v1)):
        px = ox + uc * L * u[0] + vc * L * v[0]
        py = oy + uc * L * u[1] + vc * L * v[1]
        corners.append((float(px), float(py)))

    xs = [c[0] for c in corners]
    ys = [c[1] for c in corners]
    x0 = int(max(0, math.floor(min(xs))))
    y0 = int(max(0, math.floor(min(ys))))
    x1 = int(min(img_w - 1, math.ceil(max(xs))))
    y1 = int(min(img_h - 1, math.ceil(max(ys))))
    cx = sum(xs) / 4.0
    cy = sum(ys) / 4.0
    return x0, y0, max(1, x1 - x0), max(1, y1 - y0), (cx, cy), corners


def map_regions_grid(
    landmarks: FaceLandmarks,
    config: dict,
    img_w: int,
    img_h: int,
    pts68: np.ndarray | None = None,
) -> List[RegionRect]:
    """九行三列网格 → 25 个相邻、不重叠的色部矩形"""
    L, u, v, origin = compute_baseline(landmarks)
    grid = config["grid"]

    if grid.get("dynamic_from_68", False) and pts68 is not None and len(pts68) == 68:
        row_bounds, col_bounds = compute_grid_bounds_from_68(pts68, origin, u, v, L)
    else:
        row_bounds = list(grid["row_bounds_L"])
        half_w = estimate_face_half_width_L(landmarks, u, origin, L)
        col_bounds = _resolve_col_bounds(grid, half_w)

    out: List[RegionRect] = []
    for cell in config["cells"]:
        row = cell["row"]
        col = cell["col"]
        u0, v0, u1, v1 = _cell_uv_rect(row, col, row_bounds, col_bounds)
        x, y, w, h, center, quad = _uv_rect_to_pixels(
            u0, v0, u1, v1, origin, u, v, L, img_w, img_h
        )
        out.append(
            RegionRect(
                id=cell["id"],
                name=cell["name"],
                side=cell["side"],
                x=x,
                y=y,
                w=w,
                h=h,
                center=center,
                size_L=(round(u1 - u0, 4), round(v1 - v0, 4)),
                quad=quad,
                grid_row=row,
                grid_col=col,
            )
        )
    out.sort(key=lambda r: r.id)
    return out


def map_regions(
    landmarks: FaceLandmarks,
    config: dict,
    img_w: int,
    img_h: int,
    pts68: np.ndarray | None = None,
) -> List[RegionRect]:
    """根据配置 layout 选择映射方式"""
    layout = config.get("layout", "center_expand")
    if layout == "grid_nine_rows":
        return map_regions_grid(landmarks, config, img_w, img_h, pts68=pts68)
    raise ValueError(f"不支持的 layout: {layout}")


def regions_to_dict(
    regions: List[RegionRect],
    L: float,
    layout: str = "grid_nine_rows",
    row_bounds: List[float] | None = None,
    col_bounds: List[float] | None = None,
) -> Dict:
    payload = {
        "layout": layout,
        "dynamic_from_68": row_bounds is not None,
        "zhongting_L": L,
        "count": len(regions),
        "regions": [
            {
                "id": r.id,
                "name": r.name,
                "side": r.side,
                "grid_row": r.grid_row,
                "grid_col": r.grid_col,
                "bbox": [r.x, r.y, r.w, r.h],
                "quad": [[p[0], p[1]] for p in r.quad],
                "center": list(r.center),
                "size_L": list(r.size_L),
            }
            for r in regions
        ],
    }
    if row_bounds is not None:
        payload["row_bounds_L"] = row_bounds
    if col_bounds is not None:
        payload["col_bounds_L"] = col_bounds
    return payload


def clamp_regions(regions: List[RegionRect], img_w: int, img_h: int) -> List[RegionRect]:
    """边界裁剪（相邻格共享边，裁剪仅作用于贴图边缘）"""
    fixed = []
    for r in regions:
        x = max(0, min(r.x, img_w - 1))
        y = max(0, min(r.y, img_h - 1))
        w = max(1, min(r.w, img_w - x))
        h = max(1, min(r.h, img_h - y))
        fixed.append(
            RegionRect(
                r.id, r.name, r.side, x, y, w, h, r.center, r.size_L, r.quad, r.grid_row, r.grid_col
            )
        )
    return fixed
