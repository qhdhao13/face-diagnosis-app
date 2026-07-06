# face-diagnosis-app

> 古籍面诊养生 · 鸿蒙原生 APP / 元服务 · 传统文化娱乐养生自测工具

> 传统文化娱乐养生自测工具 · 非医疗软件 · 零医疗属性

## 产品定位

基于《黄帝内经·灵枢·五色》《望诊遵经》王鸿谟《中医色诊学》三本古籍，提供**古人养生观察参考**与**生活调理科普**，仅供文化娱乐与日常养护参考。

## 技术栈

- **IDE**: DevEco Studio 5.0+
- **语言**: ArkTS 纯原生
- **SDK**: HarmonyOS API 12 (5.0.0)
- **架构**: 8 大独立模块，完全解耦可插拔

## 模块化架构

```
entry/src/main/ets/
├── common/                    # 公共层
│   ├── types/AppTypes.ets     # 全局类型与模块接口
│   ├── constants/AppConstants.ets  # 合规文案/常量
│   ├── utils/LocalStorageUtil.ets  # 本地存储
│   ├── ModuleRegistry.ets     # 模块注册中心
│   └── AppBootstrap.ets       # 启动引导
├── modules/
│   ├── permission/            # 模块1：权限管理
│   ├── camera/                # 模块2：相机采集
│   ├── vision/                # 模块3：云端视觉 + 本地规则兜底
│   │   ├── pipeline/          # RuleVisionPipeline（离线兜底）
│   │   └── VisionModule.ets
│   ├── knowledge/             # 模块4：古籍知识库
│   ├── wellness/              # 模块5：四维养生方案
│   ├── compliance/            # 模块7：合规+联网授权
│   └── settings/              # 模块8：独立设置配置
├── services/
│   ├── CloudVisionService.ets    # 云端多模态视觉（主路径）
│   ├── TextGenerationService.ets # 双模型文案生成
│   └── DiagnosisOrchestrator.ets # 自测流程编排
├── components/                # UI组件
├── pages/                     # 页面（模块6报告UI）
├── formability/               # 元服务卡片能力
└── widget/                    # 元服务卡片UI
```

## 8 大模块说明

| 模块 | 目录 | 职责 |
|------|------|------|
| 1 权限管理 | `modules/permission/` | 相机/网络动态授权 |
| 2 相机采集 | `modules/camera/` | 前置拍照，内存缓存，用完即删 |
| 3 视觉分析 | `modules/vision/` + `CloudVisionService` | 云端 VL 看脸（主）+ RGB 规则兜底 |
| 4 古籍知识库 | `modules/knowledge/` | 三本古籍静态库，零幻觉匹配 |
| 5 养生方案 | `modules/wellness/` | 饮食/运动/作息/情绪四维方案 |
| 6 报告UI | `pages/ReportPage.ets` | 报告渲染+古籍溯源展示 |
| 7 合规风控 | `modules/compliance/` | 敏感词过滤+免责+联网授权 |
| 8 设置配置 | `modules/settings/` | 基础信息/模型/版本/开发者 |

## 双模型体系（联网 · 用户自备 Key）

- **官方推荐**（默认）：通义千问 OpenAI 兼容 API
  - 视觉：`qwen-vl-plus`（看脸分析）
  - 文案：`qwen-turbo`（古籍双译）
- **私有会员模型**：需会员注册 + 开发者审批（测试 ID 前缀 `VIP_`），用户自备 Token + API 地址
- **离线兜底**：断网 / 无 Key / 拒绝联网 → 本地规则引擎 + 静态古籍解析

> 所有大模型 **不打包进 App**；在设置页填写 API Key 后启用云端能力。

## 合规红线

- 严禁医疗词汇（诊断、治疗、病症等 30+ 敏感词自动过滤）
- 继续使用即同意：面部照片将上传至用户配置的 AI 服务分析
- 分析完成后应用内立即销毁本地图像副本
- 启动强制免责弹窗
- 联网需用户主动授权（单次/永久/拒绝）

## 快速开始

1. 用 **DevEco Studio 5.0+** 打开 **`face-diagnosis-app`** 项目根目录
2. 配置签名（File → Project Structure → Signing Configs）
3. 连接鸿蒙设备或启动模拟器
4. **设置 → 模型与 API 配置**：填写通义 DashScope **API Key**
5. 点击 Run 编译运行

## 自测流程（云端主路径）

```
CameraKit 拍照
  → 联网授权弹窗（首次 / 未授权时）
  → CloudVisionService（qwen-vl-plus 多模态看脸）
  → 古籍评分匹配(37条)
  → TextGenerationService（qwen-turbo 双译文案）
  → 四维养生方案 → 报告 → 销毁图像
```

**降级路径（不上传照片）：**

```
断网 / 无 API Key / 拒绝联网 / 云端 API 失败
  → RuleVisionPipeline（RGB 规则 + 人脸框）
  → 离线古籍解析文案
```

**引擎优先级（AUTO 模式）：**

```
CloudVisionService（已配置 Key + 联网授权）
    ↓ 失败或未就绪
RuleVisionPipeline（本地规则）
```

真机 HiLog 过滤：`hilog | grep -E 'CloudVisionService|VisionModule|ScanPage'`

报告字段 `analysisEngine` 标注实际引擎：`cloud_vision` | `rule` | `cloud_fallback_rule`

## 端侧 .om 模型（备选方案 · 已降级）

历史方案 C（MTCNN + MobileNetV3 + MobileCLIP 端侧推理）代码仍保留于 `modules/vision/`，但 **当前主路径为云端视觉**。若需启用端侧管线，见：

- [docs/MODELS_SOURCES.md](docs/MODELS_SOURCES.md)
- [docs/MODEL_CONVERT_GUIDE.md](docs/MODEL_CONVERT_GUIDE.md)
- [docs/MODEL_ALTERNATIVES.md](docs/MODEL_ALTERNATIVES.md)

## 开发者信息

- 微信：qhdhao
- 邮箱：qhdhao@126.com

## 许可证

本应用所有代码、功能、文案均为开发者原创，禁止未经授权商用。
