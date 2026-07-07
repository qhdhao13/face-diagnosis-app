"""
由 iBUG 68 关键点动态计算九行三列格线（每张图自适应）
比例参照《灵枢·五色》古法分区示意 → 映射二十五明堂 9×3 格

定稿版本：grid v2.2（2026-07-07）
参考图：docs/agc/reference-lingshu-wuse-partition.png
验收：validate_grid_visual.py + validate.py
"""
from __future__ import annotations

from typing import List, Tuple

import numpy as np

Point = Tuple[float, float]

# 九行十界静态比例（兜底）
_STATIC_ROW_BOUNDS = [-1.75, -1.15, -0.72, -0.16, 0.22, 0.52, 1.19, 1.42, 1.66, 2.19]
_STATIC_COL_BOUNDS = [-1.08, -0.32, 0.32, 1.08]

# --- 古法参考图 → 二十五明堂 比例系数 ---
# 上庭：「庭」大、「阙」薄（参考图额心占眉上区域约 3/4）
_REF_TIANTING_OF_UPPER = 0.75
# 发际延伸、眉弓延伸
_HAIRLINE_EXTEND_L = 0.48
_BROW_EXTEND_MIN_L = 1.15
_BROW_EXTEND_RATIO = 1.85
# 山根上缘：眉内侧略上（用户已确认山根位置）
_SHANGEN_TOP_OFFSET = 0.04
# 鼻柱：年上/寿上分界（参考图明堂区偏长）
_REF_NIAN_SHOU_SPLIT = 0.55
# 准头格高（鼻尖窄带，参考图「鼻准」适中）
_MIN_ZHUN_SPAN_L = 0.34


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
    out = [bounds[0]]
    for i in range(1, len(bounds)):
        out.append(max(bounds[i], out[-1] + eps))
    return out


def _lerp_bounds(static: List[float], v_lo: float, v_hi: float) -> List[float]:
    s0, s1 = static[0], static[-1]
    span = s1 - s0
    if span < 1e-6:
        return static
    return [v_lo + (s - s0) / span * (v_hi - v_lo) for s in static]


def _estimate_hairline_v(pts68: np.ndarray, origin: Point, u: np.ndarray, v: np.ndarray, L: float) -> float:
    """发际 v：全脸最上缘再向上（参考图「庭」贴发际）"""
    top_idx = int(np.argmin(pts68[:, 1]))
    _, v_highest = _pt_uv(pts68[top_idx], origin, u, v, L)
    return v_highest - _HAIRLINE_EXTEND_L


def _upper_row_bounds_from_landmarks(
    v_top: float,
    v_brow_mid: float,
    v_nasal_root: float,
    v_eye_upper: float,
) -> Tuple[float, float, float, float]:
    """
    上庭三行（参考图：庭大、阙薄、山根在眉间）
    """
    shangen_bot = max(v_nasal_root + 0.04, v_eye_upper - 0.01)
    shangen_bot = min(shangen_bot, v_eye_upper + 0.05)

    border_que_shangen = v_brow_mid - _SHANGEN_TOP_OFFSET

    # 眉上区域按参考图 75:25 分天庭/阙中
    court_span = max(border_que_shangen - v_top, 0.28)
    tianting_bot = v_top + court_span * _REF_TIANTING_OF_UPPER

    return v_top, tianting_bot, border_que_shangen, shangen_bot


def _lower_row_bounds_from_landmarks(
    shangen_bot: float,
    v_nose_tip: float,
    v_nose_base: float,
    v_upper_lip: float,
    v_lower_lip: float,
    v_chin: float,
) -> List[float]:
    """
    中下庭（参考图：鼻柱长、准头在鼻尖、人中于鼻下沟）
    """
    zhun_half = _MIN_ZHUN_SPAN_L / 2.0
    zhun_top = v_nose_tip - zhun_half
    zhun_bot = v_nose_tip + zhun_half

    bridge_span = max(zhun_top - shangen_bot, 0.12)
    nian_bot = shangen_bot + bridge_span * _REF_NIAN_SHOU_SPLIT

    ren_top = zhun_bot + 0.02
    ren_bot = v_upper_lip + 0.03

    cheng_top = max(ren_bot + 0.02, v_lower_lip - 0.03)
    cheng_bot = v_chin - 0.14

    return _enforce_monotonic([
        nian_bot,
        zhun_top,
        zhun_bot,
        ren_bot,
        cheng_top,
        cheng_bot,
        v_chin + 0.12,
    ])


def compute_grid_bounds_from_68(
    pts68: np.ndarray,
    origin: Point,
    u: np.ndarray,
    v: np.ndarray,
    L: float,
) -> Tuple[List[float], List[float]]:
    def uv(i: int) -> Tuple[float, float]:
        return _pt_uv(pts68[i], origin, u, v, L)

    _, v_brow_top_r = uv(17)
    _, v_brow_top_l = uv(26)
    v_brow_top = min(v_brow_top_r, v_brow_top_l)
    _, v_brow = uv(19)
    _, v_brow_l = uv(24)
    v_brow_mid = (v_brow + v_brow_l) / 2.0
    _, v_nasal_root = uv(27)
    eye_upper_vs = [uv(i)[1] for i in (37, 38, 43, 44)]
    v_eye_upper = min(eye_upper_vs)
    _, v_nose_tip = uv(33)
    _, v_nose_base = uv(30)
    _, v_upper_lip = uv(51)
    _, v_lower_lip = uv(57)
    _, v_chin = uv(8)

    brow_span = max(v_brow_mid - v_brow_top, 0.06)
    v_top_brow = v_brow_top - max(_BROW_EXTEND_MIN_L, brow_span * _BROW_EXTEND_RATIO)
    v_hairline = _estimate_hairline_v(pts68, origin, u, v, L)
    v_top = min(v_top_brow, v_hairline)

    v0, v1, v2, v3 = _upper_row_bounds_from_landmarks(
        v_top, v_brow_mid, v_nasal_root, v_eye_upper,
    )
    lower_tail = _lower_row_bounds_from_landmarks(
        v3, v_nose_tip, v_nose_base, v_upper_lip, v_lower_lip, v_chin,
    )

    row_bounds = _enforce_monotonic([v0, v1, v2, v3] + lower_tail)

    u_jaw_r, _ = uv(0)
    u_jaw_l, _ = uv(16)
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
