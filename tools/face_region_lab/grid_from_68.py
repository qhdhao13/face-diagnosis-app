"""
由 iBUG 68 关键点动态计算九行三列格线（每张图自适应）
策略：用 68 点确定脸廓与五官锚点，再按静态模板比例插值，保证左右三列等宽、九行比例稳定
"""
from __future__ import annotations

from typing import List, Tuple

import numpy as np

Point = Tuple[float, float]

# 静态模板（regions_25.json 兜底值），用于保持古籍明堂行高比例
_STATIC_ROW_BOUNDS = [-1.38, -0.92, -0.58, -0.16, 0.22, 0.52, 1.19, 1.42, 1.66, 2.19]
_STATIC_COL_BOUNDS = [-1.08, -0.32, 0.32, 1.08]


def _pt_uv(
    p: np.ndarray,
    origin: Point,
    u: np.ndarray,
    v: np.ndarray,
    L: float,
) -> Tuple[float, float]:
    dx = float(p[0]) - origin[0]
    dy = float(p[1]) - origin[1]
    return (dx * u[0] + dy * u[1]) / L, (dx * v[0] + dy * v[1]) / L


def _enforce_monotonic(bounds: List[float], eps: float = 0.015) -> List[float]:
    """保证格线边界严格递增，避免格高为 0"""
    out = [bounds[0]]
    for i in range(1, len(bounds)):
        out.append(max(bounds[i], out[-1] + eps))
    return out


def _lerp_bounds(static: List[float], v_lo: float, v_hi: float) -> List[float]:
    """将静态 L 倍数边界线性映射到 [v_lo, v_hi]"""
    s0, s1 = static[0], static[-1]
    span = s1 - s0
    if span < 1e-6:
        return static
    return [v_lo + (s - s0) / span * (v_hi - v_lo) for s in static]


def compute_grid_bounds_from_68(
    pts68: np.ndarray,
    origin: Point,
    u: np.ndarray,
    v: np.ndarray,
    L: float,
) -> Tuple[List[float], List[float]]:
    """
    根据 68 点位置生成 row_bounds_L / col_bounds_L（单位：L 倍数）
    行：眉上缘→颏，按静态九行比例插值
    列：脸廓左右三等分
    """
    def uv(i: int) -> Tuple[float, float]:
        return _pt_uv(pts68[i], origin, u, v, L)

    # --- 行锚点 ---
    _, v_brow_top_r = uv(17)
    _, v_brow_top_l = uv(26)
    v_brow_top = min(v_brow_top_r, v_brow_top_l)
    _, v_brow = uv(19)
    _, v_brow_l = uv(24)
    v_brow_mid = (v_brow + v_brow_l) / 2.0
    _, v_shangen = uv(27)
    _, v_chin = uv(8)

    # 额顶：眉上再向上延伸（至少 0.35L，或与眉-山根间距成比例）
    brow_to_shangen = max(v_shangen - v_brow_mid, 0.08)
    v_top = v_brow_top - max(0.35, brow_to_shangen * 0.9)
    v_bottom = v_chin + 0.12

    row_bounds = _enforce_monotonic(_lerp_bounds(_STATIC_ROW_BOUNDS, v_top, v_bottom))

    # --- 列：脸廓三等分 ---
    u_jaw_r, _ = uv(0)   # 被摄者右
    u_jaw_l, _ = uv(16)  # 被摄者左
    u_cheek_r, _ = uv(14)
    u_cheek_l, _ = uv(2)
    u_outer_r = max(u_jaw_r, u_cheek_r)
    u_outer_l = min(u_jaw_l, u_cheek_l)
    if u_outer_l > u_outer_r:
        u_outer_l, u_outer_r = u_outer_r, u_outer_l

    width = max(u_outer_r - u_outer_l, 0.6)
    third = width / 3.0
    col_bounds = _enforce_monotonic([
        u_outer_l,
        u_outer_l + third,
        u_outer_l + 2.0 * third,
        u_outer_r,
    ])

    return row_bounds, col_bounds
