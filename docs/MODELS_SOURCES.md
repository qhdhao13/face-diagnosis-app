# 项目模型清单与获取来源

> 本文档汇总 **face-diagnosis-app** 用到的全部 AI 模型：端侧视觉（离线）+ 文本文案（联网 API）。  
> 与代码目录、rawfile 文件名一一对应。

---

## 总览

| 类别 | 数量 | 部署方式 | 是否需联网 |
|------|------|----------|------------|
| 端侧视觉模型 | 3 个 | 下载 → 转换 → 打入 `rawfile/models/` | ❌ 离线 |
| 文本解析大模型 | 2 套（官方 / 私有） | HTTP API 调用 | ✅ 需用户授权联网 |

**重要说明（端侧三模型）：**  
魔搭 / HuggingFace 下载的通常是 **ONNX / PyTorch / MindSpore 原始格式**，**不能**直接改名为 `.om` 使用。  
必须经 **MindSpore Lite Converter（`converter_lite`）** 转为鸿蒙端侧格式（`.ms`，本项目 rawfile 中命名为 `.om`）。  
转换步骤见 [MODEL_CONVERT_GUIDE.md](./MODEL_CONVERT_GUIDE.md)。

---

## 一、端侧视觉模型（Module 3 · 离线）

放置目录：

```
entry/src/main/resources/rawfile/models/
  mtcnn.om           ← Stage1 人脸定位
  mobilenetv3.om     ← Stage2 面部分区
  mobileclip.om      ← Stage3 气色 / 肤色 / 纹理特征
  model_config.json
  complexion_tag_embeddings.json
```

### 1. MTCNN 人脸轻量检测（相机人脸定位）

| 项目 | 说明 |
|------|------|
| **App 文件名** | `mtcnn.om` |
| **作用** | 拍照后定位人脸框，供后续分区与气色分析 |
| **推荐来源** | [魔搭社区 ModelScope](https://modelscope.cn) |
| **搜索关键词** | `mtcnn-light` |
| **特点** | 开源免费、移动端专用、体量小，适合鸿蒙端侧 |

**获取步骤：**

1. 打开 https://modelscope.cn ，搜索 **mtcnn-light**
2. 下载模型文件（常见为 ONNX 或 MindSpore）
3. 用 `converter_lite` 转为 `.ms`，复制并重命名为 `mtcnn.om`
4. 按模型说明调整 `model_config.json` 中 `mtcnn` 段的 `inputWidth/Height/mean/scale/dataFormat`

**备选（快速打通链路）：** ONNX Model Zoo **UltraFace**，见 `tools/face_model/`，文件名仍用 `mtcnn.om`。

---

### 2. MobileNetV3-Lite 面部分割（额头 / 脸颊 / 下巴）

| 项目 | 说明 |
|------|------|
| **App 文件名** | `mobilenetv3.om` |
| **作用** | 在人脸框内划分额头、双颊、下巴等区域 |
| **推荐来源** | [HuggingFace](https://huggingface.co/models) 或 [魔搭 ModelScope](https://modelscope.cn) |
| **搜索关键词** | `mobilenetv3_lite_segment` |
| **特点** | 移动端量化版，体积极小，适合手机端侧 |

**获取步骤：**

1. 在 HuggingFace 或魔搭搜索 **mobilenetv3_lite_segment**
2. 下载分割模型（ONNX / TFLite 等）
3. 转换为 `mobilenetv3.om` 放入 rawfile
4. 对齐 `model_config.json` → `mobilenetv3`，并按真实输出调整 `OmOutputParser.parseSegmentationMask`

> **注意：** 普通 ImageNet 分类版 MobileNetV3 **不能**替代分割模型；必须带 segment / parsing 头。

---

### 3. MobileCLIP 轻量多模态（气色 / 肤色 / 纹理）

| 项目 | 说明 |
|------|------|
| **App 文件名** | `mobileclip.om` |
| **作用** | 提取面部图像 embedding，与封闭气色词表匹配 |
| **推荐来源** | [魔搭 ModelScope](https://modelscope.cn) |
| **搜索关键词** | `mobileclip-chinese-light` |
| **特点** | 适配中文场景，图像特征匹配，适合古籍面诊封闭词表 |

**获取步骤：**

1. 魔搭搜索 **mobileclip-chinese-light** 并下载
2. 转换为 `mobileclip.om`
3. 用**同一模型**对 `AppConstants.ComplexionTypes` 中的封闭词离线计算 embedding
4. 写入 `complexion_tag_embeddings.json`（替换当前占位数据）

---

### 端侧部署检查清单

- [ ] 三个 `.om` 均已放入 `rawfile/models/`（可只放 `mtcnn.om` 分步验证）
- [ ] `model_config.json` 与模型输入尺寸、归一化一致
- [ ] DevEco Rebuild 安装
- [ ] HiLog：`[OmModelLoader] Runner=1/3` 或 `3/3`
- [ ] 报告 `analysisEngine`：`om_pipeline` / `om_pipeline_partial` / `rule`

---

## 二、文本解析大模型（Module 文案 · 联网）

对应代码：`services/TextGenerationService.ets` · 设置页「模型与 API 配置」

**与端侧模型的区别：** 文本模型 **不打包进 App**，通过 **HTTP API** 调用；需用户在合规弹窗中 **授权联网**。

### A. 通用公共模型（默认 · 所有用户）

| 项目 | 说明 |
|------|------|
| **代码标识** | `ModelType.OFFICIAL` |
| **用途** | 古籍原文 + 白话解读、养生文案生成 |
| **推荐服务** | 通义千问轻量版 / 智谱 GLM 轻量 API 等国内兼容 OpenAI 格式的接口 |
| **优势** | 文言理解强、古籍 RAG 解析稳定 |

**配置方式（开发者部署时）：**

1. 在服务端或代理层对接所选大模型 API
2. 将 OpenAI 兼容 endpoint 写入 `AppConstants.DefaultModelConfig.OFFICIAL_ENDPOINT`  
   或在 App **设置页**填写 API 地址
3. 若所用平台需要 Key，在设置中配置 `apiKey`（由**你方服务端**持有，勿硬编码进公开仓库）

> 设置页字段：`apiEndpoint`、`apiKey`（见 `SettingsPage.ets`）

### B. 私有会员模型（需审批）

| 项目 | 说明 |
|------|------|
| **代码标识** | `ModelType.PRIVATE` |
| **用途** | 会员专属大模型 / 私有部署 API |
| **来源** | 开发者自行提供的 Key 或私有 endpoint |
| **权限** | `ModelConfigModule.validatePrivateModelAccess()`，测试 ID 前缀 `VIP_` |

**配置方式：**

1. 用户在设置页填写 **私有 Token** 与 **API 地址**
2. 仅通过开发者审批的会员账号可调用
3. 未授权或断网时自动降级 **离线古籍静态解读**

---

## 三、模型与代码映射

```
拍照 JPEG
  → VisionModule
      Stage1  mtcnn.om          （魔搭 mtcnn-light）
      Stage2  mobilenetv3.om    （HF/魔搭 mobilenetv3_lite_segment）
      Stage3  mobileclip.om     （魔搭 mobileclip-chinese-light）
      ↓ 封闭词 + 古籍知识库匹配
  → TextGenerationService
      官方 API  /  私有会员 API
      ↓
  → ReportPage 报告
```

| 模型 | rawfile / 配置 | 主要代码 |
|------|----------------|----------|
| MTCNN | `mtcnn.om` | `OmVisionPipeline.runStage1FaceDetect` |
| MobileNetV3-Lite | `mobilenetv3.om` | `runStage2Segmentation` |
| MobileCLIP | `mobileclip.om` + `complexion_tag_embeddings.json` | `runStage3Complexion` + `ComplexionTagMapper` |
| 官方/私有 LLM | 设置页 API 配置 | `TextGenerationService.generateOnline` |

---

## 四、相关文档

- [MODEL_CONVERT_GUIDE.md](./MODEL_CONVERT_GUIDE.md) — 端侧 ONNX → MindSpore Lite 转换与真机验证
- [README.md](../README.md) — 架构与 Module 3 分层管线
- `entry/src/main/resources/rawfile/models/MODELS.txt` — rawfile 放置说明

---

## 五、常见误区

1. **魔搭下载后直接改后缀为 .om** → 会加载失败，必须先 `converter_lite`
2. **把文本大模型当端侧模型下载** → 文案模型走 API，不进 rawfile
3. **三个视觉模型必须齐套才能测** → 已支持只放 `mtcnn.om` 分步验证 Stage1
4. **「无需 Token 的公共 API」** → 通常指终端用户无需自备 Key；**开发者**仍需在后台或设置中配置合法 endpoint / 密钥
