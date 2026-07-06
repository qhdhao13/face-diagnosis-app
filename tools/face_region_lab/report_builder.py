"""
色诊报告构建：25 区分项 + 综合汇总
"""
from __future__ import annotations

from typing import Any, Dict, List

from color_analysis import LabStats, RegionColorResult, compute_face_baseline

# 上下庭分组（综合传变判断）
UPPER_REGIONS = {"天庭", "阙中", "山根", "右日角", "左日角", "右月角", "左月角", "右阙", "左阙"}
MIDDLE_REGIONS = {"年上", "寿上", "准头", "右山根", "左山根", "右卧蚕", "左卧蚕", "右鼻翼", "左鼻翼"}
LOWER_REGIONS = {"人中", "承浆", "地阁", "右颧骨", "左颧骨", "右法令", "左法令"}

# 脏腑近似映射（明堂色部 → 汇总结论用，非医疗诊断）
ORGAN_MAP = {
    "天庭": "心/上焦",
    "阙中": "肺",
    "山根": "肝/胆",
    "年上": "脾",
    "寿上": "脾/胃",
    "准头": "脾胃",
    "人中": "肾/生殖",
    "承浆": "肾/下焦",
    "地阁": "肾/下焦",
}


def _lab_to_dict(lab: LabStats) -> Dict[str, Any]:
    return {
        "L": lab.L,
        "a": lab.a,
        "b": lab.b,
        "chroma": lab.chroma,
        "L_std": lab.L_std,
        "a_std": lab.a_std,
        "b_std": lab.b_std,
    }


def _region_to_dict(r: RegionColorResult) -> Dict[str, Any]:
    return {
        "id": r.id,
        "name": r.name,
        "side": r.side,
        "dominant_color": r.dominant_color,
        "pathology_hint": r.pathology_hint,
        "floating_sinking": r.floating_sinking,
        "lustre": r.lustre,
        "scatter_cluster": r.scatter_cluster,
        "interpretation": r.interpretation,
        "lab": _lab_to_dict(r.lab),
        "sample_count": r.sample_count,
        "confidence": r.confidence,
    }


def _count_abnormal(results: List[RegionColorResult]) -> Dict[str, int]:
    """统计异常五色频次"""
    counts: Dict[str, int] = {"青": 0, "赤": 0, "黄": 0, "白": 0, "黑": 0}
    for r in results:
        if r.dominant_color in counts and r.dominant_color != "白":
            counts[r.dominant_color] += 1
        elif r.dominant_color == "白" and r.lustre in ("枯槁", "略晦"):
            counts["白"] += 1
    return counts


# 五色 → 古籍表述（《灵枢·五色》）
COLOR_CLASSICAL = {
    "青": "寒瘀",
    "赤": "热盛",
    "黄": "湿困",
    "白": "气虚",
    "黑": "寒凝",
}


def _rank_colors(counts: Dict[str, int], min_count: int = 2) -> List[tuple]:
    ranked = [(k, v) for k, v in counts.items() if v >= min_count]
    ranked.sort(key=lambda x: -x[1])
    return ranked


def _count_court_color(results: List[RegionColorResult], court_names: set, color: str) -> int:
    return sum(1 for r in results if r.name in court_names and r.dominant_color == color)


def _summarize_lustre(results: List[RegionColorResult]) -> str:
    dry = sum(1 for r in results if r.lustre in ("枯槁", "略晦"))
    if dry >= 8:
        return "多区晦暗枯槁，光泽不足，正气欠充；"
    if dry >= 3:
        return "部分色部光泽略减；"
    return "大部色部尚有润泽；"


def _summarize_floating(results: List[RegionColorResult]) -> str:
    floating = sum(1 for r in results if r.floating_sinking == "浮")
    sinking = sum(1 for r in results if r.floating_sinking == "沉")
    if floating > sinking + 3:
        return "浮象偏多，色在表者众；"
    if sinking > floating + 3:
        return "沉象偏多，色在里者众；"
    return ""


def _build_overall_conclusion(
    results: List[RegionColorResult],
    color_counts: Dict[str, int],
) -> str:
    """《灵枢·五色》体例整体结论"""
    ranked = _rank_colors(color_counts)
    lustre_note = _summarize_lustre(results)
    float_note = _summarize_floating(results)

    if not ranked:
        return (
            "据《灵枢·五色》观二十五明堂：诸部色象大体调匀，明润有泽，未见显著偏胜之色。"
            "宜顺时调摄起居饮食，以保中和。此为古籍色诊文化自察参考，不作医事依据。"
        )

    color_phrase = "、".join(
        f"{c}（{COLOR_CLASSICAL.get(c, '偏象')}）" for c, _ in ranked[:3]
    )
    heat_upper = _count_court_color(results, UPPER_REGIONS, "赤")
    heat_middle = _count_court_color(results, MIDDLE_REGIONS, "赤")
    damp_lower = _count_court_color(results, LOWER_REGIONS, "黄")

    trend_parts = []
    if heat_upper >= 1 and heat_middle >= 1:
        trend_parts.append("上中二庭热象并见，有热势内传之虞")
    if heat_middle >= 1 and (
        _count_court_color(results, LOWER_REGIONS, "青")
        + _count_court_color(results, LOWER_REGIONS, "黑")
        >= 1
    ):
        trend_parts.append("中庭热象与下庭寒象相杂，寒热错杂")
    if damp_lower >= 3:
        trend_parts.append("下庭黄象偏盛，湿困趋于下焦")
    trend = "；".join(trend_parts) + "；" if trend_parts else "三庭色象各有偏重而未成明显传变链；"

    return (
        f"据《灵枢·五色》合参二十五明堂色部：全面色象以{color_phrase}等偏盛为主。"
        f"{trend}{lustre_note}{float_note}"
        "合而观之，宜从起居、饮食、情志诸端慎为调摄。此为古籍养生文化自测参考，不作医事依据。"
    )


def _build_five_color_overview(color_counts: Dict[str, int]) -> str:
    ranked = _rank_colors(color_counts, min_count=1)
    if not ranked:
        return "《灵枢·五色》以明润匀称为要：今观诸部大体符合，青赤黄白黑未见显著偏胜。"
    lines = [
        "《灵枢·五色》曰：「五色必以明为准」；又曰：「青者肝象，赤者心象，黄者脾象，白者肺象，黑者肾象」。"
    ]
    for color, count in ranked[:3]:
        lines.append(f"今{color}色偏盛于{count}处，主{COLOR_CLASSICAL.get(color, '偏象')}之候。")
    return "".join(lines)


def _build_court_paragraph(
    court_label: str,
    court_classic: str,
    court_names: set,
    results: List[RegionColorResult],
) -> str:
    """某一庭古籍分论"""
    court_regions = [r for r in results if r.name in court_names]
    notable = [
        r
        for r in court_regions
        if r.dominant_color != "白" or r.lustre != "有泽" or r.scatter_cluster == "抟"
    ]
    if not notable:
        return f"{court_label}（{court_classic}）：诸部明润尚匀，色象平和。"

    color_counts: Dict[str, int] = {}
    for r in notable:
        color_counts[r.dominant_color] = color_counts.get(r.dominant_color, 0) + 1
    top = sorted(color_counts.items(), key=lambda x: -x[1])[:2]
    color_text = "、".join(f"{c}偏盛" for c, _ in top)
    region_text = "、".join(r.name for r in notable[:4])

    floating = sum(1 for r in notable if r.floating_sinking == "浮")
    sinking = sum(1 for r in notable if r.floating_sinking == "沉")
    float_text = ""
    if floating > sinking and floating >= 2:
        float_text = "，多色浮于外，象在表"
    elif sinking > floating and sinking >= 2:
        float_text = "，多色沉于内，象在里"

    dry = sum(1 for r in notable if r.lustre in ("枯槁", "略晦"))
    lustre_text = "；部分色部光泽不足，宜慎养正气" if dry >= 2 else ""
    return f"{court_label}（{court_classic}）：{region_text}等部{color_text}{float_text}{lustre_text}。"


def _build_classic_hint(results: List[RegionColorResult]) -> str:
    sinking = sum(1 for r in results if r.floating_sinking == "沉")
    floating = sum(1 for r in results if r.floating_sinking == "浮")
    quote = "《灵枢·五色》：「色沉者病在里，色浮者病在表。」"
    if sinking > floating:
        quote += " 今观沉象较多，合参当留意里象之养。"
    elif floating > sinking:
        quote += " 今观浮象较多，合参当留意表象之调。"
    else:
        quote += " 今观浮沉相当，宜表里兼顾。"
    quote += " 《望诊遵经》亦强调以明堂明润、五色匀称为先。"
    return quote


def _court_summary(results: List[RegionColorResult], court_names: set) -> List[str]:
    """某一庭的异常摘要（供 JSON 结构化字段）"""
    lines = []
    for r in results:
        if r.name not in court_names:
            continue
        if r.dominant_color != "白" or r.lustre != "有泽" or r.scatter_cluster == "抟":
            lines.append(r.interpretation)
    return lines


def _build_transmission_text(results: List[RegionColorResult]) -> str:
    """传变合参段落"""
    upper_heat = _count_court_color(results, UPPER_REGIONS, "赤")
    middle_heat = _count_court_color(results, MIDDLE_REGIONS, "赤")
    lower_cold = _count_court_color(results, LOWER_REGIONS, "青") + _count_court_color(
        results, LOWER_REGIONS, "黑"
    )
    hints = []
    if upper_heat >= 1 and middle_heat >= 1:
        hints.append("上庭见赤，中庭亦赤，据色诊传变之说，热象有内传之势")
    if middle_heat >= 1 and lower_cold >= 1:
        hints.append("中庭热象与下庭寒象并见，寒热相杂，宜合参调摄")
    scatter_heavy = sum(1 for r in results if r.scatter_cluster == "抟")
    scatter_light = sum(1 for r in results if r.scatter_cluster == "散")
    if scatter_heavy >= 5:
        hints.append("多区色块凝聚，象偏「抟」，古以色抟者久病根深，宜久养")
    elif scatter_light >= 5:
        hints.append("多区色象散漫，象偏「散」，古以色散者病轻或新起")
    if not hints:
        hints.append("三庭色象各自偏重，未见显著上下传变链，宜分部位合参下方分项")
    return "；".join(hints) + "。"


def build_summary(results: List[RegionColorResult]) -> Dict[str, Any]:
    """综合汇总：古籍体例，不含 Lab 数值"""
    baseline = compute_face_baseline(results)
    color_counts = _count_abnormal(results)

    upper = _court_summary(results, UPPER_REGIONS)
    middle = _court_summary(results, MIDDLE_REGIONS)
    lower = _court_summary(results, LOWER_REGIONS)

    transmission = []
    if _count_court_color(results, UPPER_REGIONS, "赤") >= 1 and _count_court_color(
        results, MIDDLE_REGIONS, "赤"
    ) >= 1:
        transmission.append("上庭见赤，中庭亦赤，热邪有内传之势")
    if _count_court_color(results, MIDDLE_REGIONS, "赤") >= 1 and (
        _count_court_color(results, LOWER_REGIONS, "青")
        + _count_court_color(results, LOWER_REGIONS, "黑")
        >= 1
    ):
        transmission.append("中庭热象与下庭寒象并见，寒热错杂")
    if not transmission:
        transmission.append("各区色象相对独立，未见明显传变链")

    organ_notes = []
    for r in results:
        if r.name in ORGAN_MAP and r.dominant_color != "白":
            organ_notes.append(f"{ORGAN_MAP[r.name]}（{r.name}）见{r.dominant_color}，{r.pathology_hint}")

    overall = _build_overall_conclusion(results, color_counts)
    five_colors = _build_five_color_overview(color_counts)
    upper_para = _build_court_paragraph("上庭", "上焦·心肺", UPPER_REGIONS, results)
    middle_para = _build_court_paragraph("中庭", "中焦·脾胃", MIDDLE_REGIONS, results)
    lower_para = _build_court_paragraph("下庭", "下焦·肾命", LOWER_REGIONS, results)
    transmission_para = _build_transmission_text(results)
    classic_hint = _build_classic_hint(results)

    summary_text = "\n\n".join(
        [
            f"【整体结论】\n{overall}",
            f"【五色总象】\n{five_colors}",
            f"【三庭分论】\n{upper_para}\n\n{middle_para}\n\n{lower_para}",
            f"【传变合参】\n{transmission_para}",
            f"【典籍提示】\n{classic_hint}",
        ]
    )

    return {
        "baseline_lab": _lab_to_dict(baseline),
        "color_abnormal_counts": color_counts,
        "upper_court": upper,
        "middle_court": middle,
        "lower_court": lower,
        "transmission_hints": transmission,
        "organ_correlation": organ_notes[:8],
        "overall_conclusion": overall,
        "summary_text": summary_text,
        "disclaimer": "本结果为古籍色诊文化自测参考，仅供养生自察，如有不适请就医。",
    }


def build_color_report(
    results: List[RegionColorResult],
    image_path: str = "",
    engine: str = "",
) -> Dict[str, Any]:
    """
    完整色诊报告 JSON
    regions 固定 25 条，每项独立一行 interpretation
    """
    if len(results) != 25:
        raise ValueError(f"必须 25 区结果，当前 {len(results)}")

    per_region = [_region_to_dict(r) for r in sorted(results, key=lambda x: x.id)]
    summary = build_summary(results)

    # 分项一行列表（便于日志 / LLM 输入）
    line_items = [r["interpretation"] for r in per_region]

    return {
        "version": "1.0",
        "source_image": image_path,
        "landmark_engine": engine,
        "region_count": 25,
        "analysis_mode": "per_region_independent",
        "regions": per_region,
        "line_items": line_items,
        "summary": summary,
    }
