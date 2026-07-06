"""
关键点提供模块
优先 MediaPipe Face Mesh，可选 dlib 68 点；输出语义锚点（山根、准头、中轴）
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

import cv2
import numpy as np

Point = Tuple[float, float]


@dataclass
class FaceLandmarks:
    """人脸关键点与语义锚点"""
    points: np.ndarray  # shape (N, 2) 像素坐标
    shangen: Point      # 山根
    zhuntou: Point      # 准头
    midline_pts: List[Point]  # 中轴采样点
    engine: str         # mediapipe | dlib | json


# MediaPipe Face Mesh → iBUG 68 点索引（0–67 顺序与 dlib 一致）
# 来源：社区广泛使用的 468→68 对应表（StackOverflow / mediapipe2dlib）
MEDIAPIPE_IBUG_68: List[int] = [
    # 0–16 下颌轮廓（被摄者右→左）
    162, 234, 93, 58, 172, 136, 149, 148, 152, 377, 378, 365, 397, 288, 323, 454, 389,
    # 17–21 右眉（图像左侧）
    71, 63, 105, 66, 107,
    # 22–26 左眉（图像右侧）
    336, 296, 334, 293, 301,
    # 27–35 鼻
    168, 197, 5, 4, 75, 97, 2, 326, 305,
    # 36–41 右眼（图像左侧）
    33, 160, 158, 133, 153, 144,
    # 42–47 左眼（图像右侧）
    362, 385, 387, 263, 373, 380,
    # 48–59 外唇
    61, 39, 37, 0, 267, 269, 291, 405, 314, 17, 84, 181,
    # 60–67 内唇
    78, 82, 13, 312, 308, 317, 14, 87,
]

# MediaPipe Face Mesh 常用语义索引
MP_IDX = {
    "glabella": 168,   # 眉间 / 近山根
    "nose_bridge": 6,
    "nose_tip": 1,     # 准头 / 鼻尖
    "chin": 152,
    "left_eye_outer": 33,
    "right_eye_outer": 263,
}


def _load_image_bgr(path: Path):
    import cv2
    img = cv2.imread(str(path))
    if img is None:
        raise FileNotFoundError(f"无法读取图片: {path}")
    return img


def detect_mediapipe_image(img_bgr: np.ndarray) -> Optional[FaceLandmarks]:
    """MediaPipe 检测（已解码 BGR 图像）"""
    try:
        import mediapipe as mp
        from mediapipe.tasks import python as mp_python
        from mediapipe.tasks.python import vision
    except ImportError:
        return None

    model_path = Path(__file__).parent / "models" / "face_landmarker.task"
    if not model_path.exists():
        return None

    h, w = img_bgr.shape[:2]
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=img_bgr[:, :, ::-1].copy())

    base_options = mp_python.BaseOptions(model_asset_path=str(model_path))
    options = vision.FaceLandmarkerOptions(
        base_options=base_options,
        running_mode=vision.RunningMode.IMAGE,
        num_faces=1,
    )

    with vision.FaceLandmarker.create_from_options(options) as landmarker:
        result = landmarker.detect(mp_image)
        if not result.face_landmarks:
            return None
        lm = result.face_landmarks[0]
        pts = np.array([[p.x * w, p.y * h] for p in lm], dtype=np.float64)

    sh = _avg_points(pts, [MP_IDX["glabella"], MP_IDX["nose_bridge"]])
    zh = tuple(pts[MP_IDX["nose_tip"]])
    mid = [
        tuple(pts[MP_IDX["glabella"]]),
        tuple(pts[MP_IDX["nose_tip"]]),
        tuple(pts[MP_IDX["chin"]]),
    ]
    return FaceLandmarks(points=pts, shangen=sh, zhuntou=zh, midline_pts=mid, engine="mediapipe")


def detect_mediapipe(image_path: Path) -> Optional[FaceLandmarks]:
    """使用 MediaPipe Face Landmarker（tasks API，478 点）"""
    img = _load_image_bgr(image_path)
    return detect_mediapipe_image(img)


def detect_dlib_image(img_bgr: np.ndarray, predictor_path: Optional[Path] = None) -> Optional[FaceLandmarks]:
    """dlib 68 点（已解码 BGR 图像）"""
    try:
        import dlib
    except ImportError:
        return None

    if predictor_path is None:
        predictor_path = Path(__file__).parent / "models" / "shape_predictor_68_face_landmarks.dat"
    if not predictor_path.exists():
        return None

    detector = dlib.get_frontal_face_detector()
    predictor = dlib.shape_predictor(str(predictor_path))
    gray = img_bgr[:, :, ::-1].mean(axis=2).astype(np.uint8)
    faces = detector(gray, 1)
    if len(faces) == 0:
        return None

    shape = predictor(gray, faces[0])
    pts = np.array([[shape.part(i).x, shape.part(i).y] for i in range(68)], dtype=np.float64)
    sh = _avg_points(pts, [27, 28])
    zh = tuple(pts[33])
    mid = [tuple(pts[27]), tuple(pts[33]), tuple(pts[8])]
    return FaceLandmarks(points=pts, shangen=sh, zhuntou=zh, midline_pts=mid, engine="dlib")


def detect_dlib(image_path: Path, predictor_path: Optional[Path] = None) -> Optional[FaceLandmarks]:
    """使用 dlib 68 点（需 shape_predictor_68_face_landmarks.dat）"""
    img = _load_image_bgr(image_path)
    return detect_dlib_image(img, predictor_path)


def load_from_json(json_path: Path) -> FaceLandmarks:
    """从 JSON 加载（测试用）：含 shangen, zhuntou, points 可选"""
    data = json.loads(json_path.read_text(encoding="utf-8"))
    sh = tuple(data["shangen"])
    zh = tuple(data["zhuntou"])
    mid = [tuple(p) for p in data.get("midline_pts", [sh, zh])]
    pts = np.array(data.get("points", [sh, zh]), dtype=np.float64)
    return FaceLandmarks(points=pts, shangen=sh, zhuntou=zh, midline_pts=mid, engine="json")


def detect(image_path: Path, prefer: str = "auto") -> FaceLandmarks:
    """
    统一检测入口
    prefer: auto | mediapipe | dlib
    """
    if prefer == "dlib":
        lm = detect_dlib(image_path)
        if lm is not None:
            return lm
        raise RuntimeError("dlib 检测失败，请确认已安装 dlib 并放置 shape_predictor_68_face_landmarks.dat")

    if prefer == "mediapipe":
        lm = detect_mediapipe(image_path)
        if lm is not None:
            return lm
        raise RuntimeError("MediaPipe 未检测到人脸")

    # auto：MediaPipe 优先，dlib 备选
    lm = detect_mediapipe(image_path)
    if lm is not None:
        return lm
    lm = detect_dlib(image_path)
    if lm is not None:
        return lm
    raise RuntimeError("未检测到人脸（已尝试 MediaPipe 与 dlib）")


def detect_from_bytes(image_bytes: bytes, prefer: str = "auto") -> FaceLandmarks:
    """从 JPEG/PNG 字节流检测人脸关键点（云端 API 用）"""
    arr = np.frombuffer(image_bytes, dtype=np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError("无法解码图片")

    if prefer == "dlib":
        lm = detect_dlib_image(img)
        if lm is not None:
            return lm
        raise RuntimeError("dlib 检测失败")

    if prefer == "mediapipe":
        lm = detect_mediapipe_image(img)
        if lm is not None:
            return lm
        raise RuntimeError("MediaPipe 未检测到人脸")

    lm = detect_mediapipe_image(img)
    if lm is not None:
        return lm
    lm = detect_dlib_image(img)
    if lm is not None:
        return lm
    raise RuntimeError("未检测到人脸（已尝试 MediaPipe 与 dlib）")


def _avg_points(pts: np.ndarray, indices: List[int]) -> Point:
    xs = [pts[i][0] for i in indices]
    ys = [pts[i][1] for i in indices]
    return float(np.mean(xs)), float(np.mean(ys))


def extract_68_points(landmarks: FaceLandmarks) -> np.ndarray:
    """
    提取 iBUG 标准 68 点（像素坐标）
    dlib 直接返回；MediaPipe 按 MEDIAPIPE_IBUG_68 映射
    """
    pts = landmarks.points
    if landmarks.engine == "dlib" and len(pts) == 68:
        return pts.copy()
    if len(pts) <= max(MEDIAPIPE_IBUG_68):
        raise ValueError(f"关键点数量不足，无法映射 68 点: {len(pts)}")
    return pts[MEDIAPIPE_IBUG_68].copy()
