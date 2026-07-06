"""
二十五色部色彩分析（与几何/绘图解耦）
强制逐区独立：裁剪 → 光照均衡 → 剔瑕疵 → Lab 统计
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional, Tuple

import cv2
import numpy as np

from region_mapper import RegionRect

# 单区最少有效像素，低于此值 confidence 降级
MIN_SAMPLE_COUNT = 30


@dataclass
class LabStats:
    """Lab 色彩统计量"""
    L: float
    a: float
    b: float
    L_std: float
    a_std: float
    b_std: float
    chroma: float
    sample_count: int


@dataclass
class RegionColorResult:
    """单色部分析结果"""
    id: int
    name: str
    side: str
    lab: LabStats
    sample_count: int
    confidence: float
    # 由 ling_shu_rules 填充
    dominant_color: str = ""
    floating_sinking: str = ""
    lustre: str = ""
    scatter_cluster: str = ""
    pathology_hint: str = ""
    interpretation: str = ""


def _quad_to_mask(quad: List[Tuple[float, float]], h: int, w: int) -> np.ndarray:
    """四边形 ROI 掩膜"""
    mask = np.zeros((h, w), dtype=np.uint8)
    pts = np.array([[int(round(p[0])), int(round(p[1]))] for p in quad], dtype=np.int32)
    cv2.fillPoly(mask, [pts], 255)
    return mask


def crop_quad_masked(image_bgr: np.ndarray, quad: List[Tuple[float, float]]) -> Tuple[np.ndarray, np.ndarray]:
    """
    按四边形掩膜裁剪色部区域
    返回：(BGR 像素块仅含掩膜内, 布尔掩膜)
    """
    h, w = image_bgr.shape[:2]
    mask = _quad_to_mask(quad, h, w)
    return image_bgr.copy(), mask


def correct_illumination(patch_bgr: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """
    光照均衡：对 L 通道做 CLAHE（限制对比度自适应直方图均衡）
    仅作用于掩膜内像素，避免整图色偏影响单区判断
    """
    lab = cv2.cvtColor(patch_bgr, cv2.COLOR_BGR2LAB)
    l_ch, a_ch, b_ch = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(4, 4))
    l_eq = clahe.apply(l_ch)
    # 仅替换掩膜内
    out_lab = lab.copy()
    idx = mask > 0
    out_lab[:, :, 0][idx] = l_eq[idx]
    return cv2.cvtColor(out_lab, cv2.COLOR_LAB2BGR)


def remove_artifacts(
    patch_bgr: np.ndarray,
    mask: np.ndarray,
) -> np.ndarray:
    """
    剔除瑕疵像素：高光、死黑、极端离群
    返回更新后的掩膜（原 mask 与剔除规则相交）
    """
    lab = cv2.cvtColor(patch_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    idx = mask > 0
    if idx.sum() == 0:
        return mask

    L_full = lab[:, :, 0]
    a_full = lab[:, :, 1]
    b_full = lab[:, :, 2]

    # 全白高光（BGR 近 255）
    bgr = patch_bgr.astype(np.float32)
    highlight = (bgr[:, :, 0] > 250) & (bgr[:, :, 1] > 250) & (bgr[:, :, 2] > 250)

    # 过暗阴影
    shadow = L_full < 15

    # Lab 离群：距中位数超过 2.5 倍 MAD（仅在掩膜内统计）
    l_med = float(np.median(L_full[idx]))
    a_med = float(np.median(a_full[idx]))
    b_med = float(np.median(b_full[idx]))
    l_mad = float(np.median(np.abs(L_full[idx] - l_med))) + 1e-3
    a_mad = float(np.median(np.abs(a_full[idx] - a_med))) + 1e-3
    b_mad = float(np.median(np.abs(b_full[idx] - b_med))) + 1e-3
    outlier = (
        (np.abs(L_full - l_med) > 2.5 * l_mad * 1.4826)
        | (np.abs(a_full - a_med) > 2.5 * a_mad * 1.4826)
        | (np.abs(b_full - b_med) > 2.5 * b_mad * 1.4826)
    )

    clean = mask.copy()
    clean[highlight] = 0
    clean[shadow] = 0
    clean[outlier & (mask > 0)] = 0
    return clean


def extract_lab_stats(patch_bgr: np.ndarray, mask: np.ndarray) -> LabStats:
    """掩膜内 Lab 均值与离散度"""
    lab = cv2.cvtColor(patch_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    idx = mask > 0
    n = int(idx.sum())
    if n == 0:
        return LabStats(0, 0, 0, 0, 0, 0, 0, 0)

    L = lab[:, :, 0][idx]
    a = lab[:, :, 1][idx] - 128.0  # OpenCV Lab 偏移校正到标准 a*
    b = lab[:, :, 2][idx] - 128.0

    mean_l = float(np.mean(L))
    mean_a = float(np.mean(a))
    mean_b = float(np.mean(b))
    chroma = float(np.hypot(mean_a, mean_b))

    return LabStats(
        L=round(mean_l, 2),
        a=round(mean_a, 2),
        b=round(mean_b, 2),
        L_std=round(float(np.std(L)), 2),
        a_std=round(float(np.std(a)), 2),
        b_std=round(float(np.std(b)), 2),
        chroma=round(chroma, 2),
        sample_count=n,
    )


def _vertical_l_gradient(patch_bgr: np.ndarray, mask: np.ndarray) -> float:
    """ROI 内 L 通道上下梯度：正=上浅下深（沉），负=上深下浅（浮）"""
    lab = cv2.cvtColor(patch_bgr, cv2.COLOR_BGR2LAB).astype(np.float32)
    ys, xs = np.where(mask > 0)
    if len(ys) < 10:
        return 0.0
    L_vals = lab[ys, xs, 0]
    # 按 y 分上下半区
    y_mid = (ys.min() + ys.max()) / 2.0
    top = L_vals[ys <= y_mid]
    bot = L_vals[ys > y_mid]
    if len(top) == 0 or len(bot) == 0:
        return 0.0
    return float(np.mean(bot) - np.mean(top))


def analyze_single_region(
    image_bgr: np.ndarray,
    region: RegionRect,
    face_baseline: Optional[LabStats] = None,
) -> RegionColorResult:
    """
    单区完整流程：裁剪 → 均衡 → 剔瑕疵 → Lab
    face_baseline 供后续规则层做相对判断（在 analyze_all_regions 中统一传入）
    """
    from ling_shu_rules import classify_region

    patch, mask = crop_quad_masked(image_bgr, region.quad)
    patch = correct_illumination(patch, mask)
    clean_mask = remove_artifacts(patch, mask)
    lab = extract_lab_stats(patch, clean_mask)
    grad_l = _vertical_l_gradient(patch, clean_mask)

    confidence = 1.0
    if lab.sample_count < MIN_SAMPLE_COUNT:
        confidence = max(0.2, lab.sample_count / MIN_SAMPLE_COUNT)

    result = RegionColorResult(
        id=region.id,
        name=region.name,
        side=region.side,
        lab=lab,
        sample_count=lab.sample_count,
        confidence=round(confidence, 2),
    )

    classify_region(result, face_baseline, grad_l)
    return result


def compute_face_baseline(results: List[RegionColorResult]) -> LabStats:
    """全脸 25 区加权 Lab 基准（按采样数加权）"""
    total = sum(r.sample_count for r in results)
    if total == 0:
        return LabStats(128, 0, 0, 0, 0, 0, 0, 0)

    wL = sum(r.lab.L * r.sample_count for r in results) / total
    wa = sum(r.lab.a * r.sample_count for r in results) / total
    wb = sum(r.lab.b * r.sample_count for r in results) / total
    w_chroma = sum(r.lab.chroma * r.sample_count for r in results) / total
    return LabStats(
        L=round(wL, 2),
        a=round(wa, 2),
        b=round(wb, 2),
        L_std=0,
        a_std=0,
        b_std=0,
        chroma=round(w_chroma, 2),
        sample_count=total,
    )


def analyze_all_regions(
    image_bgr: np.ndarray,
    regions: List[RegionRect],
) -> List[RegionColorResult]:
    """
    强制 25 区独立循环，禁止 merge
    两遍：先粗算基准 → 再逐区相对诊断
    """
    assert len(regions) == 25, f"色部数量必须为 25，当前 {len(regions)}"

    # 第一遍：仅 Lab 统计
    raw: List[Tuple[RegionRect, LabStats, np.ndarray, np.ndarray, float]] = []
    for r in regions:
        patch, mask = crop_quad_masked(image_bgr, r.quad)
        patch = correct_illumination(patch, mask)
        clean = remove_artifacts(patch, mask)
        lab = extract_lab_stats(patch, clean)
        grad = _vertical_l_gradient(patch, clean)
        raw.append((r, lab, patch, clean, grad))

    # 加权基准
    tmp = [
        RegionColorResult(id=r.id, name=r.name, side=r.side, lab=lab, sample_count=lab.sample_count, confidence=1.0)
        for r, lab, _, _, _ in raw
    ]
    baseline = compute_face_baseline(tmp)

    # 第二遍：规则分类
    from ling_shu_rules import classify_region

    results: List[RegionColorResult] = []
    for r, lab, patch, clean, grad in raw:
        confidence = 1.0 if lab.sample_count >= MIN_SAMPLE_COUNT else max(0.2, lab.sample_count / MIN_SAMPLE_COUNT)
        item = RegionColorResult(
            id=r.id,
            name=r.name,
            side=r.side,
            lab=lab,
            sample_count=lab.sample_count,
            confidence=round(confidence, 2),
        )
        classify_region(item, baseline, grad)
        results.append(item)

    results.sort(key=lambda x: x.id)
    return results
