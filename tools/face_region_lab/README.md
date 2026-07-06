# 古籍二十五明堂色部 · 离线标注实验室

阶段 1 交付：在 **不改 App** 的前提下，验证《灵枢·五色》+《形色外诊简摩》25 色部几何划分。

## 安装

```bash
cd tools/face_region_lab
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
# 若缺少模型（约 3.6MB）：
# curl -L -o models/face_landmarker.task \
#   https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
```

可选 dlib 68 点：

```bash
pip install dlib
# 下载 shape_predictor_68_face_landmarks.dat 到 models/
```

## 校验配置（无需照片）

```bash
python validate.py
python demo.py   # 仅校验 regions_25.json
```

## 生成标注图

```bash
python demo.py --image /path/to/face.jpg
# 输出:
#   output/annotated.jpg
#   output/regions_pixel.json
```

## 布局 v2：九行三列网格（相邻不重叠）

- `layout: grid_nine_rows`：按《形色外诊简摩》九行思路，3 列 × 9 行，末行仅 **地阁**
- 格线坐标：`row_bounds_L` / `col_bounds_L`（均为 L 倍数），共享边、无面积重叠
- 绘制：四边形 `polylines`（随脸部旋转），非轴对齐外扩框

| 行 | 左 | 中 | 右 |
|----|----|----|-----|
| 0 | 日角 | 天庭 | 日角 |
| … | … | … | … |
| 8 | — | 地阁 | — |

## 文件说明

| 文件 | 作用 |
|------|------|
| `regions_25.json` | 25 色部系数（k×L），**名称不可增减** |
| `landmark_provider.py` | MediaPipe / dlib 关键点 |
| `region_mapper.py` | 中庭 L + 中轴 + 镜像映射 |
| `renderer.py` | 方框 + 竖排标注 |
| `validate.py` | 25 区验收 |
| `STAGE0_MATCH.md` | 与 App 差异分析 |

## 古籍约束

1. 25 区与锁定名单一一对应  
2. 左右区以中轴镜像（配置中 ox 符号相反）  
3. 宽高均为 `size_L * L`  
4. L = 山根中心 → 准头中心  

系数 v1 为草案，对照 `assets/reference_25_mingtang.png` 微调 `center_offset_L` / `size_L` 即可。

## 下一步（阶段 2，需另确认）

- 导出系数到 ArkTS `AncientColorRegion25.ets`  
- App 内 Debug 叠加层（默认关闭）
