# 端侧模型工具

## 已下载资源（本机 `output/`）

| 文件 | 用途 | 大小 |
|------|------|------|
| `output/version-RFB-320.onnx` | Stage1 人脸（UltraFace） | ~1.2MB |
| `output/onnx/mtcnn_ultraface.onnx` | 同上，供转换 | |
| `output/onnx/mobilenetv3_small_224.onnx` | Stage2 占位（MobileNetV3-Small） | ~320KB |
| `output/downloads/apple/MobileCLIP-S0/mobileclip_s0.pt` | Stage3 魔搭权重 | ~206MB |
| `output/downloads/iic/cv_manual_face-detection_mtcnn/` | MTCNN numpy 参考 | 小 |
| `models_registry.json` | 模型映射清单 | |

## 一键下载

```bash
cd tools/face_model
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt modelscope torch torchvision open-clip-torch onnxscript
python download_all_models.py
```

## 部署到 App（关键一步）

鸿蒙 **只认 MindSpore Lite `.ms`**（本项目命名为 `.om`）。**Mac 无法本地转换**，需：

### 方式 A：DevEco Studio（Windows 推荐）

1. 在 Windows 安装 DevEco，SDK 内搜索 `converter_lite`
2. 复制整个 `tools/face_model/output/onnx/` 到 Windows
3. 设置环境变量并运行：

```bat
set CONVERTER_LITE=C:\path\to\converter_lite
bash prepare_rawfile.sh
```

### 方式 B：Docker（Linux 容器）

```bash
bash convert_in_docker.sh
```

### 方式 C：手动单模型

```bash
converter_lite --fmk=ONNX \
  --modelFile=output/onnx/mtcnn_ultraface.onnx \
  --outputFile=output/ms/mtcnn \
  --inputShape="input:1,3,240,320" \
  --inputDataFormat=NCHW
cp output/ms/mtcnn.ms ../../entry/src/main/resources/rawfile/models/mtcnn.om
```

## 验证

DevEco Rebuild → 真机 HiLog：

```bash
hdc shell hilog -x | grep OmModelLoader
```

## 说明

- 魔搭搜 `mtcnn-light` 无独立 .om；已用 **UltraFace** 等价替代 Stage1
- 人体解析模型 `damo/cv_resnet101_image-multiple-human-parsing` 约 **723MB**，未打入 App；Stage2 暂用轻量 MobileNetV3 占位 + 规则分区
- MobileCLIP 完整导出需 Linux/Windows 环境（本机 HuggingFace 超时）；权重已从魔搭 `apple/MobileCLIP-S0` 下载
