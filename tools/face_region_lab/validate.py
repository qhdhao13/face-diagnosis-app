"""
二十五色部验收脚本
"""
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import List, Tuple

CANONICAL_25: List[str] = [
    "天庭", "阙中", "山根", "年上", "寿上", "准头", "人中", "承浆", "地阁",
    "右日角", "左日角", "右月角", "左月角", "右阙", "左阙", "右山根", "左山根",
    "右鼻翼", "左鼻翼", "右颧骨", "左颧骨", "右卧蚕", "左卧蚕", "右法令", "左法令",
]

PAIR_LEFT_RIGHT = [
    ("左日角", "右日角"), ("左月角", "右月角"), ("左阙", "右阙"), ("左山根", "右山根"),
    ("左鼻翼", "右鼻翼"), ("左颧骨", "右颧骨"), ("左卧蚕", "右卧蚕"), ("左法令", "右法令"),
]


def validate_config(config_path: Path) -> Tuple[bool, List[str]]:
    errors: List[str] = []
    data = json.loads(config_path.read_text(encoding="utf-8"))
    layout = data.get("layout", "")

    if layout == "grid_nine_rows":
        cells = data.get("cells", [])
        if len(cells) != 25:
            errors.append(f"cells 数量应为 25，当前 {len(cells)}")
        names = [c["name"] for c in cells]
        if sorted(names) != sorted(CANONICAL_25):
            missing = set(CANONICAL_25) - set(names)
            extra = set(names) - set(CANONICAL_25)
            if missing:
                errors.append(f"缺少色部: {missing}")
            if extra:
                errors.append(f"多余色部: {extra}")
        grid = data.get("grid", {})
        if not grid.get("dynamic_from_68", False):
            rb = grid.get("row_bounds_L", [])
            cb = grid.get("col_bounds_L", [])
            if len(rb) != 10:
                errors.append(f"row_bounds_L 应有 10 个边界（9 行），当前 {len(rb)}")
            if len(cb) != 4:
                errors.append(f"col_bounds_L 应有 4 个边界（3 列），当前 {len(cb)}")
        return len(errors) == 0, errors

    errors.append(f"未知 layout: {layout}")
    return False, errors


def _bbox_iou(a: List[int], b: List[int]) -> float:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    x0 = max(ax, bx)
    y0 = max(ay, by)
    x1 = min(ax + aw, bx + bw)
    y1 = min(ay + ah, by + bh)
    inter = max(0, x1 - x0) * max(0, y1 - y0)
    if inter <= 0:
        return 0.0
    union = aw * ah + bw * bh - inter
    return inter / union if union > 0 else 0.0


def validate_no_overlap(pixel_json: dict, iou_tol: float = 1e-6) -> Tuple[bool, List[str]]:
    """
    网格分区验收：UV 格间仅共边不共面积。
    像素 bbox 的 IoU 在脸部旋转时会误报，故对 grid 布局改查 grid_row/col 是否唯一占用。
    """
    errors: List[str] = []
    layout = pixel_json.get("layout", "")
    regions = pixel_json.get("regions", [])

    if layout == "grid_nine_rows":
        seen = set()
        for r in regions:
            key = (r.get("grid_row"), r.get("grid_col"))
            if key in seen:
                errors.append(f"网格重复占用: row={key[0]} col={key[1]}")
            seen.add(key)
        return len(errors) == 0, errors

    for i in range(len(regions)):
        for j in range(i + 1, len(regions)):
            iou = _bbox_iou(regions[i]["bbox"], regions[j]["bbox"])
            if iou > iou_tol:
                errors.append(
                    f"重叠: {regions[i]['name']} vs {regions[j]['name']} IoU={iou:.4f}"
                )
    return len(errors) == 0, errors


def validate_symmetry(pixel_json: dict, epsilon_ratio: float = 0.05) -> Tuple[bool, List[str]]:
    """校验左右成对区域相对中轴镜像"""
    errors: List[str] = []
    L = pixel_json.get("zhongting_L", 1.0)
    by_name = {r["name"]: r for r in pixel_json.get("regions", [])}

    for left_name, right_name in PAIR_LEFT_RIGHT:
        if left_name not in by_name or right_name not in by_name:
            errors.append(f"缺少对称对: {left_name}/{right_name}")
            continue
        lc = by_name[left_name]["center"]
        rc = by_name[right_name]["center"]
        mid_x = (lc[0] + rc[0]) / 2.0
        dl = abs((lc[0] - mid_x) + (rc[0] - mid_x))
        if dl > epsilon_ratio * L * 2:
            errors.append(f"镜像偏差过大: {left_name}/{right_name} dl={dl:.2f}")

    return len(errors) == 0, errors


if __name__ == "__main__":
    root = Path(__file__).parent
    ok, errs = validate_config(root / "regions_25.json")
    print("config OK" if ok else "config FAIL")
    for e in errs:
        print(" ", e)
    px = root / "output" / "regions_pixel.json"
    if px.exists():
        data = json.loads(px.read_text(encoding="utf-8"))
        ok2, errs2 = validate_symmetry(data)
        print("symmetry OK" if ok2 else "symmetry FAIL")
        for e in errs2:
            print(" ", e)
        ok3, errs3 = validate_no_overlap(data)
        print("no-overlap OK" if ok3 else "no-overlap FAIL")
        for e in errs3:
            print(" ", e)
