# 端侧视觉模型替代方案（不必拘泥 MTCNN / MobileNetV3 / MobileCLIP）

> 选型原则：**能转 MindSpore Lite、体积小、下载稳定、与现有 `OmVisionPipeline` 改动少**。  
> 你的 App 目标是「古籍气色自测」，不是刷 SOTA 榜单——**规则引擎 + 1 个小检测模型** 往往比三模型齐套更稳。

---

## 一、三种路线对比

| 路线 | Stage1 人脸 | Stage2 分区 | Stage3 气色 | App 增量 | 推荐场景 |
|------|-------------|---------------|-------------|----------|----------|
| **A 极简（推荐先做）** | UltraFace | **规则分区**（已有） | **RGB 规则**（已有） | ~1.2MB | 快速真机验证 MindSpore |
| **B 均衡** | UltraFace int8 | 规则分区 | EdgeFace-XXS embedding | ~5MB | 想要 embedding 又控体积 |
| **C 完整 AI** | SCRFD-500m | BiSeNet 人脸解析 | MobileCLIP-S0 | **60MB+** | 后期迭代，不急 |

**为什么 A 最合理：** Stage2/3 你已有 `FaceRegionLayout` + `ImageColorAnalyzer`，合规封闭词表也围绕 RGB/规则设计；强行上 CLIP 还要重算 `complexion_tag_embeddings.json`。

---

## 二、Stage1 人脸定位（替代 MTCNN）

| 模型 | 体积 | 输入 | 格式 | 下载 | 与项目匹配 |
|------|------|------|------|------|------------|
| **UltraFace RFB-320** ⭐ | 1.2MB | 320×240 | ONNX | [ONNX Model Zoo](https://github.com/onnx/models/tree/main/validated/vision/body_analysis/ultraface) | ✅ 已下载，`detectorType=ultraface` |
| **UltraFace RFB-320-int8** | 0.44MB | 320×240 | ONNX | 同上 zoo 的 int8 版 | ✅ 更小，需改 parser 阈值 |
| **MediaPipe BlazeFace** | ~0.5MB | 128×128 | TFLite | Google MediaPipe | ⚠️ 需 `--fmk=TFLITE` 转换，HarmonyOS 有先例 |
| **SCRFD-500m** | ~2–5MB | 640×640 或 320×240 | ONNX | InsightFace / 魔搭 SCRFD 系列 | ⚠️ 多输出头，要改 `OmOutputParser` |
| 魔搭 MTCNN numpy | 很小 | 多阶段 | .npy | `iic/cv_manual_face-detection_mtcnn` | ❌ 非单 buffer，不适合 `loadModelFromBuffer` |

**结论：** 继续用 **UltraFace** 作为 `mtcnn.om` 槽位内容即可，不必再找「mtcnn-light」。

---

## 三、Stage2 面部分区（替代 MobileNetV3-Lite segment）

| 方案 | 体积 | 说明 | 建议 |
|------|------|------|------|
| **规则分区 `FaceRegionLayout`** ⭐ | 0 | 基于人脸框切额头/双颊/下巴 | **默认采用**，代码已上线 |
| BiSeNet ResNet18 人脸解析 | ~51MB ONNX | 19 类语义分割，含额头/颊/鼻/唇 | 体积过大，不推荐进 App |
| 魔搭人体解析 ResNet101 | ~723MB | 已下载过 | ❌ 绝对不要打包 |
| ImageNet MobileNetV3 分类 | ~10MB | **不是分割** | ❌ 当前占位 ONNX 无分区能力 |

**结论：** Stage2 **不必上 AI 模型**。古籍面诊按区域看色，`FaceRegionLayout.buildRegions(faceBox)` 足够；等 Stage1 稳定后再考虑 BiSeNet 精简版。

---

## 四、Stage3 气色特征（替代 MobileCLIP）

| 方案 | 体积 | 输出 | 与封闭词表 | 建议 |
|------|------|------|------------|------|
| **`ImageColorAnalyzer` RGB** ⭐ | 0 | 偏白/偏黄/暗沉等 | ✅ 直接匹配 `ComplexionTypes` | **默认采用** |
| EdgeFace-XXS | ~7MB | 512 维人脸 embedding | ⚠️ 需离线算词表向量，非文本 CLIP | B 路线可选 |
| MobileCLIP-S0 | ~206MB | 图文 embedding | ⚠️ 词表要重算，导出 ONNX 难 | 后期再上 |
| MobileNet 分类 | ~3–13MB | 1000 类 ImageNet | ❌ 与气色词无关 | 不用 |

**结论：** 「气色」在你项目里本质是 **肤色 RGB + 区域统计**，不是开放域图文检索；**RGB 规则比 CLIP 更贴合规、更可控**。

---

## 五、文本大模型（替代方案，仍是 API）

| 服务 | 特点 | 接入方式 |
|------|------|----------|
| **通义千问 qwen-turbo** ⭐ | 文言/古文理解好，OpenAI 兼容 | 已写入 `DefaultModelConfig`，设置页填 Key |
| 智谱 GLM-4-Flash | 轻量、国内快 | 换 endpoint + model 名 |
| 私有部署 | 会员专属 | `ModelType.PRIVATE` + Token |

无需下载模型文件，与端侧 `.om` 无关。

---

## 六、推荐落地组合（给 face-diagnosis-app）

### 组合 1：最小可行 AI 面诊（强烈推荐）

```
UltraFace (mtcnn.om)  →  人脸框
FaceRegionLayout      →  分区（无模型）
ImageColorAnalyzer    →  气色（无模型）
TextGenerationService →  通义 API 写报告（可选联网）
```

- **只需转换 1 个 ONNX** → `mtcnn.om`
- 报告 `analysisEngine`：`om_pipeline_partial`
- 与「不着急上架、先验证链路」完全一致

### 组合 2：加 embedding（可选）

在组合 1 基础上，Stage3 换 **EdgeFace-XXS**（112×112，mean/std 0.5），用 embedding 余弦匹配封闭词表——比 MobileCLIP 小一个数量级。

### 组合 3：全 AI（后期）

UltraFace + BiSeNet-lite（需自训练蒸馏到 <5MB）+ 小 CLIP 或自训练气色分类头——工作量大，上架前不必做。

---

## 七、下载地址速查

```bash
# Stage1 UltraFace（国内可用 ghproxy）
curl -L -o ultraface.onnx \
  "https://ghproxy.net/https://github.com/onnx/models/raw/main/validated/vision/body_analysis/ultraface/models/version-RFB-320.onnx"

# Stage1 量化版（更小）
curl -L -o ultraface-int8.onnx \
  "https://ghproxy.net/https://github.com/onnx/models/raw/main/validated/vision/body_analysis/ultraface/models/version-RFB-320-int8.onnx"

# Stage2 人脸解析（仅研究用，51MB）
curl -L -o face_parsing.onnx \
  "https://github.com/yakhyo/face-parsing/releases/download/weights/resnet18.onnx"

# Stage3 EdgeFace（PyTorch，需再 export ONNX）
# https://huggingface.co/Idiap/EdgeFace-XXS
# 魔搭: apple/MobileCLIP-S0（已下载 mobileclip_s0.pt）
```

---

## 八、与现有代码的改动量

| 替代项 | 需改文件 | 工作量 |
|--------|----------|--------|
| UltraFace 作 Stage1 | 无（已支持） | ✅ 0 |
| Stage2 用规则 | 无（已是 fallback） | ✅ 0 |
| Stage3 用 RGB | 无（`OmVisionPipeline` 混合模式） | ✅ 0 |
| 换 SCRFD | `OmOutputParser` + `model_config.json` | 中 |
| 换 BiSeNet | 新增 mask 解析 + 区域映射 | 大 |
| 换 EdgeFace | 新 embedding 维度 + 词表 JSON | 中 |

---

## 九、一句话建议

**不要等三个「指定模型」齐套。** 先用 **UltraFace 一个 .om** 做人脸框，分区与气色继续用你已在真机跑通的 **规则引擎**——这就是最适合「古籍面诊自测」的替代方案。

转换步骤：`tools/face_model/prepare_rawfile.sh`（仅需 `mtcnn` 一行即可，可删 mobilenetv3/mobileclip 转换）。
