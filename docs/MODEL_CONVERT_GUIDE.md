# 端侧模型转换指南（Stage1 起 · 分步验证）

> 目标：把 **魔搭 / HuggingFace 下载的模型** 转为鸿蒙 MindSpore Lite 格式，放入 App 离线推理。  
> **模型清单与搜索关键词：** 见 [MODELS_SOURCES.md](./MODELS_SOURCES.md)

---

## 〇、与「直接下载部署」的关系

| 步骤 | 做什么 |
|------|--------|
| ① 下载 | 魔搭搜 `mtcnn-light` 等，得到 ONNX/PyTorch |
| ② 转换 | **必须** 用 `converter_lite` → `.ms`（本项目命名为 `.om`） |
| ③ 放入 App | `entry/src/main/resources/rawfile/models/` |
| ④ 真机验证 | HiLog + 拍照报告 |

**为什么不能跳过②：** 鸿蒙 `@kit.MindSporeLiteKit` 只认 MindSpore Lite 二进制 buffer，魔搭原始文件不能改后缀直接使用。

---

## 一、整体思路

```
开源 ONNX（下载）
    ↓  PC 上 ONNX Runtime 验证
MindSpore Lite Converter（converter_lite）
    ↓  生成 .ms 文件
重命名为 mtcnn.om 放入 rawfile
    ↓  DevEco 编译安装
真机拍照 → HiLog 确认 Runner 加载 + 人脸框
```

**为什么 Stage1 也可用 UltraFace 快速验证：**

| 对比项 | 魔搭 mtcnn-light | UltraFace RFB-320（备选） |
|--------|------------------|---------------------------|
| 获取 | modelscope.cn 搜索 | ONNX Model Zoo / `tools/face_model/` |
| 与产品命名 | 一致 | 文件名仍用 `mtcnn.om` |
| 转换难度 | 视具体包而定 | 低，适合先打通链路 |

项目 rawfile 槽位名 **`mtcnn.om`** 对应 Stage1；内容来自魔搭 **mtcnn-light** 或备选 UltraFace 均可。

---

## 二、准备环境（PC / Mac）

### 2.1 Python 验证环境

```bash
cd tools/face_model
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
python download_ultraface.py
python validate_onnx.py
```

### 2.2 MindSpore Lite 转换器

从以下任一途径获取 `converter_lite`：

1. **DevEco Studio SDK**（与项目 API 12 一致）  
   在 DevEco 安装目录下搜索 `converter_lite`
2. **MindSpore Lite 官方发布包**  
   https://github.com/mindspore-ai/mindspore-lite/releases

官方文档：[使用 MindSpore Lite 进行模型转换](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/mindspore-lite-converter-guidelines)

---

## 三、ONNX → .ms → mtcnn.om

### 3.1 下载（已完成可跳过）

```bash
python download_ultraface.py
# 输出: tools/face_model/output/version-RFB-320.onnx
```

来源：[ONNX Model Zoo · UltraFace](https://github.com/onnx/models/tree/main/validated/vision/body_analysis/ultraface)

### 3.2 转换命令

```bash
export CONVERTER_LITE=/path/to/converter_lite
chmod +x convert_to_ms.sh
./convert_to_ms.sh
```

或手动执行：

```bash
converter_lite \
  --fmk=ONNX \
  --modelFile=tools/face_model/output/version-RFB-320.onnx \
  --outputFile=tools/face_model/output/mtcnn \
  --inputShape="input:1,3,240,320" \
  --inputDataFormat=NCHW \
  --outputDataFormat=NHWC
```

生成 `mtcnn.ms` 后复制到：

```
entry/src/main/resources/rawfile/models/mtcnn.om
```

> **说明：** 鸿蒙官方后缀是 `.ms`；本项目 rawfile 约定用 `.om`，**内容格式相同**，只是文件名。

### 3.3 与 App 配置对齐

`model_config.json` 中 `mtcnn` 段已预设：

| 字段 | 值 | 含义 |
|------|-----|------|
| inputWidth | 320 | 宽 |
| inputHeight | 240 | 高 |
| meanR/G/B | 127 | 减均值 |
| scale | 0.0078125 | 即 1/128 |
| dataFormat | NCHW | 与 UltraFace 一致 |
| detectorType | ultraface | 双输出解析 |

**若转换失败：** 检查 `--inputShape` 是否与 ONNX 输入名一致（`validate_onnx.py` 会打印 input name）。

---

## 四、DevEco 编译与真机验证

### 4.1 编译

1. DevEco Studio 打开项目
2. **Build → Build Hap(s)/APP(s)**

> 只需放入 `mtcnn.om` 即可分步验证，**不必等三个模型齐套**。

### 4.2 HiLog

```bash
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc shell hilog -x \
  | grep -E 'OmModelLoader|MindSporeModelRunner|VisionModule'
```

期望日志：

```
[OmModelLoader] 文件=1/3, Runner=1/3, 全量就绪=false
[MindSporeModelRunner] 模型已加载: mtcnn
[VisionModule] .om 管线已就绪（主路径）
```

拍照后报告页 `analysisEngine` 可能为 `om_pipeline_partial`（仅 Stage1 AI，Stage2/3 仍规则兜底）。

### 4.3 常见问题

| 现象 | 原因 | 处理 |
|------|------|------|
| `加载失败 mtcnn` | 算子不支持 / 转换参数错误 | 换 opset 12 的 ONNX；查 MindSpore 算子支持列表 |
| 推理成功但无人脸框 | 阈值过高 / 输出顺序变化 | 看 `MindSporeModelRunner 输出[i] len=`；调 `OmOutputParser` 阈值 |
| 人脸框偏移 | mean/scale 或 NCHW 不一致 | 对照 `validate_onnx.py` 与 `model_config.json` |
| 仍走规则引擎 | 未放入 rawfile 或路径错 | 确认 `entry/.../rawfile/models/mtcnn.om` 存在且 Rebuild |

---

## 五、后续两阶段（概要）

### Stage2 · mobilenetv3.om（面部分区）

- **不能**直接用 ImageNet 分类 MobileNetV3
- 需要 **人脸解析（face parsing）** 模型，或继续用规则分区（当前默认）

### Stage3 · mobileclip.om（气色 embedding）

- 来源：[apple/ml-mobileclip](https://github.com/apple/ml-mobileclip)
- 转换后还需用 MobileCLIP **离线计算**封闭词表 embedding，替换 `complexion_tag_embeddings.json`

---

## 六、学习资源

- [HarmonyOS MindSpore Lite 开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/mindspore-lite-guidelines)
- [MindSpore Lite Converter 工具说明](https://www.mindspore.cn/lite/docs/en/master/converter/converter_tool.html)
- [ONNX Model Zoo · UltraFace](https://github.com/onnx/models/tree/main/validated/vision/body_analysis/ultraface)
- [Ultra-Light Face Detector 原项目](https://github.com/Linzaer/Ultra-Light-Fast-Generic-Face-Detector-1MB)

---

## 七、常见错误

1. **把 .om 当成 API 密钥去请求服务器** — 端侧模型是本地文件，无网络下载接口  
2. **只改文件名不改内容** — 空文件或非 MindSpore 格式会导致 `loadModelFromBuffer` 失败  
3. **三模型不齐就不测** — 现已支持只放 `mtcnn.om` 分步验证  
4. **MTCNN 三网络直接转换** — 建议先用 UltraFace 打通链路，再考虑 SCRFD / MTCNN 定制导出
