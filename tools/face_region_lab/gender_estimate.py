"""
基于 68 点人脸关键点的性别启发式估计（文化自测辅助，非身份证明）
"""
from __future__ import annotations

from typing import Any, Dict, List, Tuple

import numpy as np


def _dist(a: np.ndarray, b: np.ndarray) -> float:
    """两点欧氏距离"""
    return float(np.linalg.norm(a - b))


def estimate_gender_from_68(points: List[Tuple[float, float]]) -> Dict[str, Any]:
    """
    用下颌宽、颧骨宽、脸高等比例粗判性别
    返回 gender（男/女/未知）与 confidence（0~1）
    """
    if len(points) < 17:
        return {"gender": "未知", "confidence": 0.0}

    pts = np.array(points, dtype=np.float64)

    # 下颌最宽：轮廓点 0 与 16
    jaw_width = _dist(pts[0], pts[16])
    # 颧骨附近宽：点 2 与 14
    cheek_width = _dist(pts[2], pts[14])
    # 脸高：眉间(27) 到下巴(8)
    face_height = _dist(pts[27], pts[8])

    if face_height < 1.0 or jaw_width < 1.0:
        return {"gender": "未知", "confidence": 0.0}

    jaw_ratio = jaw_width / face_height
    cheek_jaw_ratio = cheek_width / jaw_width

    # 男性常见：下颌相对更宽、颧骨相对下颌更窄
    male_score = 0.0
    if jaw_ratio >= 0.74:
        male_score += 0.35
    if jaw_ratio >= 0.80:
        male_score += 0.25
    if cheek_jaw_ratio <= 0.93:
        male_score += 0.25
    if cheek_jaw_ratio <= 0.88:
        male_score += 0.15

    if male_score >= 0.45:
        gender = "男"
        confidence = min(0.88, 0.42 + male_score * 0.45)
    else:
        gender = "女"
        confidence = min(0.88, 0.42 + (1.0 - male_score) * 0.45)

    return {
        "gender": gender,
        "confidence": round(confidence, 2),
        "jaw_ratio": round(jaw_ratio, 3),
        "cheek_jaw_ratio": round(cheek_jaw_ratio, 3),
    }


def check_profile_gender(profile_gender: str, detected: Dict[str, Any]) -> Dict[str, Any]:
    """
    对比用户设置性别与照片估计性别
    profile_gender: 男 / 女 / 未设置
    """
    normalized = (profile_gender or "").strip()
    if normalized in ("", "未设置"):
        return {"mismatch": False, "warning": ""}

    det_gender = str(detected.get("gender", "未知"))
    det_conf = float(detected.get("confidence", 0.0))

    if det_gender == "未知" or det_conf < 0.52:
        return {
            "mismatch": False,
            "warning": "未能可靠识别照片中面部性别特征，请确认本人正脸自拍且资料正确。",
        }

    if normalized != det_gender:
        return {
            "mismatch": True,
            "warning": (
                f"您设置的性别为「{normalized}」，当前照片面部特征更接近「{det_gender}」。"
                f"请确认是否为本人，或到「设置」中修改性别后重拍。"
            ),
        }

    return {"mismatch": False, "warning": ""}
