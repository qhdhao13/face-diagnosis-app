"""
《灵枢·五色》规则层：五色 / 浮沉 / 泽夭 / 散抟
输入 Lab 统计 + 基准，输出病机标签与解读句
"""
from __future__ import annotations

from typing import Optional

from color_analysis import LabStats, RegionColorResult

# 五色 → 病机（《灵枢·五色》简表）
COLOR_PATHOLOGY = {
    "青": "主瘀寒",
    "赤": "主热",
    "黄": "主湿虚",
    "白": "主气虚",
    "黑": "主肾虚寒凝",
}


def classify_dominant_color(lab: LabStats, baseline: LabStats) -> str:
    """
    辨五色：相对全脸基准判断主色
    da=lab.a-baseline.a, db=lab.b-baseline.b, dL=lab.L-baseline.L
    """
    da = lab.a - baseline.a
    db = lab.b - baseline.b
    dL = lab.L - baseline.L
    chroma = lab.chroma

    scores = {
        "赤": max(0, da) * 1.2 + max(0, lab.a - 5) * 0.3,
        "青": max(0, -da) * 1.2 + max(0, -lab.a - 5) * 0.3,
        "黄": max(0, db) * 1.0 + max(0, lab.b - 5) * 0.3,
        "白": max(0, dL) * 0.8 + max(0, 25 - chroma) * 0.5 if lab.L > 140 else 0,
        "黑": max(0, -dL) * 0.9 + max(0, 15 - lab.L) * 0.4 if lab.L < 110 else 0,
    }

    # 接近基准、色差不明显 → 偏「白」气平
    if chroma < 8 and abs(da) < 4 and abs(db) < 4:
        return "白"

    best = max(scores, key=scores.get)
    if scores[best] < 2.0:
        return "白"
    return best


def classify_floating_sinking(grad_l: float) -> str:
    """
    辨浮沉：色浮病在表，色沉病入里
    grad_l > 0 表示下深上浅 → 沉；反之为浮
    """
    if grad_l > 4.0:
        return "沉"
    if grad_l < -4.0:
        return "浮"
    return "平"


def classify_lustre(lab: LabStats) -> str:
    """
    辨泽夭：明亮有泽 vs 晦暗枯槁
    高 L + 适中彩度 + 低 L_std → 有泽
    """
    if lab.L >= 130 and lab.chroma >= 10 and lab.L_std < 18:
        return "有泽"
    if lab.L < 100 or lab.chroma < 6 or lab.L_std > 28:
        return "枯槁"
    if lab.L < 115 and lab.chroma < 10:
        return "略晦"
    return "有泽"


def classify_scatter_cluster(lab: LabStats) -> str:
    """
    辨散抟：色散漫 vs 色块凝聚
    高 a/b 标准差 → 散；低标准差 + 高彩度 → 抟
    """
    spread = lab.a_std + lab.b_std + lab.L_std * 0.5
    if spread > 22:
        return "散"
    if spread < 12 and lab.chroma > 12:
        return "抟"
    return "平"


def build_interpretation(
    name: str,
    color: str,
    floating: str,
    lustre: str,
    scatter: str,
) -> str:
    """生成单区一行解读"""
    path = COLOR_PATHOLOGY.get(color, "")
    parts = [f"【{name}】主色{color}（{path}）"]
    if floating != "平":
        hint = "病在表" if floating == "浮" else "病入里"
        parts.append(f"色{floating}（{hint}）")
    if lustre == "枯槁":
        parts.append("晦暗枯槁，正气亏虚")
    elif lustre == "略晦":
        parts.append("光泽略减")
    if scatter == "散":
        parts.append("色散漫，病轻或新病")
    elif scatter == "抟":
        parts.append("色块凝聚，久病深重")
    return "，".join(parts)


def classify_region(
    result: RegionColorResult,
    baseline: Optional[LabStats],
    grad_l: float,
) -> None:
    """填充 RegionColorResult 诊断字段（原地修改）"""
    base = baseline or LabStats(128, 0, 0, 0, 0, 0, 0, 0)

    color = classify_dominant_color(result.lab, base)
    floating = classify_floating_sinking(grad_l)
    lustre = classify_lustre(result.lab)
    scatter = classify_scatter_cluster(result.lab)

    result.dominant_color = color
    result.floating_sinking = floating
    result.lustre = lustre
    result.scatter_cluster = scatter
    result.pathology_hint = COLOR_PATHOLOGY.get(color, "")
    result.interpretation = build_interpretation(
        result.name, color, floating, lustre, scatter
    )

    if result.confidence < 0.5:
        result.interpretation += "（采样不足，结论仅供参考）"
