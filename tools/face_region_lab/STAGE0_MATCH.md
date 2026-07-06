# 阶段 0：匹配分析报告

> 用户已确认：68 点采用 dlib / MediaPipe；执行阶段 0+1（Python + regions_25.json）。  
> 古籍约束：《灵枢·五色》+《形色外诊简摩》二十五明堂色部；中庭 L = 山根→准头。

## 1. 五条约束 vs 现有 App

| 约束 | 现有 App | 阶段 1 交付 | 阶段 2（未开始） |
|------|----------|-------------|------------------|
| 25 明堂一一对应 | `FaceRegionLayout` 仅 7 区 | `regions_25.json` + 校验脚本 | `AncientColorRegion25.ets` |
| 中庭 L 比例 | 人脸框 0–1 模板 | `region_mapper.py` | 同上 |
| 中轴镜像 | 左右模板手写 | 右区配置 + 左区 ox 取反 | Canvas 叠加 |
| 竖排标注 | 无 | OpenCV/PIL 渲染 | 可选 Debug 层 |
| 不改主路径 | experience_proxy | 仅 `tools/face_region_lab/` | 经确认再改 entry |

## 2. 68 点来源策略

| 优先级 | 引擎 | 用途 |
|--------|------|------|
| 1 | MediaPipe Face Mesh | 默认；468 点映射到语义点（山根/准头/中轴） |
| 2 | dlib 68 | 可选；`pip install dlib` 后自动启用 |
| 3 | 降级 | 无检测器时 demo 可传入 JSON 关键点 |

**山根 / 准头 / 中轴（MediaPipe 索引，见 `landmark_provider.py`）：**

- 山根：眉间 / 鼻根区（约 168、6 均值）
- 准头：鼻尖（约 1）
- 中轴线：山根—准头—颏点（168→1→152）拟合

## 3. 二十五色部 → 现有报告 8 字段（聚合，不合并算法区）

| 报告字段 | 聚合色部 |
|----------|----------|
| forehead / 天庭 | 天庭、左/右日角、月角、阙 |
| leftCheek | 左颧骨、卧蚕、法令、左山根、左鼻翼 |
| rightCheek | 右颧骨、卧蚕、法令、右山根、右鼻翼 |
| nose | 山根、年上、寿上、准头、左/右鼻翼 |
| eyeArea | 左/右卧蚕 |
| lipArea | （25 区无独立唇；仍由云端或人中下缘补充） |
| chin / 地阁 | 承浆、地阁 |
| overallComplexion | 全脸 25 区统计或云端 |

## 4. 与 experience_proxy 关系

- **并行**：25 区几何层用于标注图 / 离线取色 / 二期可视化。
- **不替代**：云端 VL 仍负责古籍语句描述；未接 App 前不影响已发布 HAP。

## 5. 验收标准（阶段 1）

- [ ] `validate.py` 通过：恰好 25 区、名称集合一致
- [ ] 8 对左右区镜像误差 < 3%·L
- [ ] 所有 w/h 为 k×L
- [ ] `demo.py` 输出 `output/annotated.jpg` + `output/regions_pixel.json`

## 6. 参考资源

- 古图：`assets/reference_25_mingtang.png`
- 系数表：`regions_25.json`（v1 草案，可调 k）
