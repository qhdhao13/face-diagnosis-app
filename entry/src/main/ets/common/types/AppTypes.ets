/**
 * 全局类型定义
 * 各模块通过接口解耦，仅依赖类型不依赖具体实现
 */

/** 模型类型枚举：官方通用 / 私有会员 */
export enum ModelType {
  OFFICIAL = 'official',
  PRIVATE = 'private'
}

/** AI 使用模式：体验免 Key（服务端白名单+配额） / 自带 Key */
export enum ModelUsageMode {
  EXPERIENCE = 'experience',
  BYOK = 'byok'
}

/** 联网授权级别 */
export enum NetworkAuthLevel {
  DENY = 'deny',
  ONCE = 'once',
  ALWAYS = 'always'
}

/** 权限申请结果 */
export interface PermissionResult {
  granted: boolean;
  permissionName: string;
  message: string;
}

/** 内存中的拍照结果（不写磁盘） */
export interface CapturedImage {
  /** JPEG 或 RGBA 原始字节 */
  data: ArrayBuffer;
  width: number;
  height: number;
  /** jpeg：相机直出；rgba：已解码像素 */
  format: 'jpeg' | 'rgba';
}

/** 面部外观特征（纯客观描述，无医疗属性） */
export interface FaceAppearanceFeature {
  overallComplexion: string;
  forehead: string;
  leftCheek: string;
  rightCheek: string;
  nose: string;
  chin: string;
  eyeArea: string;
  lipArea: string;
  details: string[];
  confidence: number;
  /** 画面平均亮度 0-255，用于光线提示 */
  averageBrightness: number;
  /** 结构化匹配标签，供古籍知识库评分使用 */
  matchTags: string[];
  /** 本次分析使用的引擎：cloud_vision | rule | cloud_fallback_rule 等 */
  analysisEngine?: string;
}

/** 25色部 Lab 单项 */
export interface Region25ColorItem {
  id: number;
  name: string;
  dominantColor: string;
  pathologyHint: string;
  floatingSinking: string;
  lustre: string;
  scatterCluster: string;
  interpretation: string;
  confidence: number;
}

/** 25色部云端会话（图片与 JSON 存服务器，App 仅持 URL） */
export interface Region25SessionResult {
  sessionId: string;
  annotatedImageUrl: string;
  originalImageUrl: string;
  reportUrl: string;
  summaryText: string;
  lineItems: string[];
  disclaimer: string;
  regions: Region25ColorItem[];
  /** 照片估计性别（男/女/未知） */
  detectedGender?: string;
  genderConfidence?: number;
  /** 与用户设置性别是否不一致 */
  genderMismatch?: boolean;
  genderWarning?: string;
}

/** 人脸检测框（归一化坐标 0-1） */
export interface FaceBoundingBox {
  x: number;
  y: number;
  width: number;
  height: number;
  confidence: number;
}

/** Module3 视觉引擎类型 */
export enum VisionEngineType {
  /** 自动：优先云端视觉，失败降级规则引擎 */
  AUTO = 'auto',
  /** 仅云端视觉 API */
  CLOUD = 'cloud',
  /** 仅本地规则引擎（RGB，不上传照片） */
  RULE = 'rule',
  /** 已弃用：端侧 .om 管线，保留枚举兼容 */
  OM_PIPELINE = 'om_pipeline'
}

/** 面部分区矩形（相对整图归一化坐标 0-1） */
export interface FaceRegionRect {
  name: string;
  xStart: number;
  xEnd: number;
  yStart: number;
  yEnd: number;
}

/** 古籍引用条目 */
export interface AncientTextEntry {
  id: string;
  source: string;
  chapter: string;
  originalText: string;
  modernExplanation: string;
  featureTags: string[];
}

/** 四维养护方案中的古籍原文引用（用户自行查阅原典） */
export interface WellnessCitation {
  entryId: string;
  source: string;
  chapter: string;
  originalText: string;
}

/** 四维养生方案（以古籍原文摘录为主） */
export interface WellnessPlan {
  diet: WellnessCitation[];
  exercise: WellnessCitation[];
  schedule: WellnessCitation[];
  emotion: WellnessCitation[];
  /** 引用说明与免责提示 */
  citationNotice: string;
}

/** 完整自测报告 */
export interface DiagnosisReport {
  reportId: string;
  timestamp: number;
  appearanceSummary: string;
  features: FaceAppearanceFeature;
  ancientReferences: AncientTextEntry[];
  culturalInterpretation: string;
  wellnessPlan: WellnessPlan;
  disclaimer: string;
  /** 体验模式 25 色部云端分析（图片存服务器） */
  region25?: Region25SessionResult;
}

/** 用户基础信息（仅本地存储） */
export interface UserProfile {
  nickname: string;
  gender: string;
  age: number;
}

/** 模型配置 */
export interface ModelConfig {
  modelType: ModelType;
  apiEndpoint: string;
  apiPort: number;
  /** 官方模型 API Key（通义等） */
  apiKey: string;
  /** 云端视觉多模态模型名，如 qwen-vl-plus */
  visionModelName: string;
  privateToken: string;
  isOfficialRecommended: boolean;
  /** 体验免 Key 或自带 Key */
  usageMode: ModelUsageMode;
}

/** 手机号注册与体验配额状态 */
export interface PhoneAuthStatus {
  phoneNumber: string;
  isRegistered: boolean;
  isWhitelisted: boolean;
  authToken: string;
  dailyFreeLimit: number;
  dailyFreeRemaining: number;
}

/** 会员权限状态 */
export interface MemberAuthStatus {
  isRegistered: boolean;
  isApproved: boolean;
  memberId: string;
}

/** 版本信息 */
export interface VersionInfo {
  currentVersion: string;
  latestVersion: string;
  updateLog: string;
  hasUpdate: boolean;
}

/** 模块接口：权限管理 */
export interface IPermissionModule {
  requestCameraPermission(): Promise<PermissionResult>;
  requestNetworkPermission(): Promise<PermissionResult>;
  checkAllPermissions(): Promise<Map<string, boolean>>;
}

/** 预览分辨率（供 XComponent Surface 适配） */
export interface PreviewSize {
  width: number;
  height: number;
}

/** 变焦范围（PhotoSession.getZoomRatioRange） */
export interface ZoomRatioRange {
  min: number;
  max: number;
}

/** 模块接口：相机采集 */
export interface ICameraModule {
  /** 绑定 UI 上下文，供 CameraKit 使用 */
  bindContext(context: Object): void;
  /** surfaceId 来自 XComponent；viewWidthPx/viewHeightPx 用于匹配预览流宽高比 */
  openCamera(surfaceId: string, viewWidthPx?: number, viewHeightPx?: number,
    onPreviewFrameStart?: () => void): Promise<boolean>;
  capturePhoto(): Promise<CapturedImage | null>;
  /** 连拍选最优 1 帧（阶段 1：端上选帧，仍只上传一张） */
  captureBestPhoto(): Promise<CapturedImage | null>;
  destroyImageData(): void;
  getLightLevel(): number;
  closeCamera(): Promise<void>;
  /** 视觉分析后回写亮度（0-255） */
  updateLightLevel(brightness: number): void;
  /** 是否正在使用前置摄像头 */
  isUsingFrontCamera(): boolean;
  /** 当前预览流分辨率 */
  getPreviewSize(): PreviewSize;
  /** 是否支持数码变焦 */
  isZoomSupported(): boolean;
  /** 变焦范围 */
  getZoomRatioRange(): ZoomRatioRange;
  /** 设置变焦倍率（1.0 为默认） */
  setZoomRatio(ratio: number): void;
}

/** 模块接口：端侧视觉识别 */
export interface IVisionModule {
  /** 启动时加载 rawfile 下的 .om 模型（可选） */
  initModels(context: Object): Promise<void>;
  analyzeFace(image: CapturedImage, profile?: UserProfile): Promise<FaceAppearanceFeature>;
  isModelReady(): boolean;
  /** 获取当前活跃引擎说明 */
  getActiveEngineLabel(): string;
}

/** 模块接口：古籍知识库 */
export interface IKnowledgeModule {
  matchByFeatures(features: FaceAppearanceFeature): AncientTextEntry[];
  getOfflineFallback(featureKey: string): AncientTextEntry | null;
}

/** 模块接口：养生方案 */
export interface IWellnessModule {
  generatePlan(entries: AncientTextEntry[], profile?: UserProfile): WellnessPlan;
}

/** 模块接口：合规风控 */
export interface IComplianceModule {
  filterSensitiveWords(text: string): string;
  validateOutput(text: string): boolean;
  getDisclaimer(): string;
  shouldShowStartupDisclaimer(): Promise<boolean>;
  markDisclaimerAccepted(): Promise<void>;
}

/** 模块接口：联网授权 */
export interface INetworkAuthModule {
  getAuthLevel(): NetworkAuthLevel;
  requestNetworkAuth(): Promise<NetworkAuthLevel>;
  canUseNetwork(): boolean;
  saveAuthLevel(level: NetworkAuthLevel): Promise<void>;
  resetAuth(): Promise<void>;
}

/** 模块接口：模型配置 */
export interface IModelConfigModule {
  getConfig(): ModelConfig;
  saveConfig(config: ModelConfig): Promise<void>;
  resetToDefault(): Promise<void>;
  validatePrivateModelAccess(): Promise<boolean>;
}

/** 模块接口：会员权限 */
export interface IMemberAuthModule {
  getStatus(): MemberAuthStatus;
  registerMember(memberId: string): Promise<boolean>;
  checkApproval(): Promise<boolean>;
  /** 按 VIP_ 规则重新判定审批（方案 A 内测） */
  refreshApproval(): Promise<boolean>;
}

/** 手机号注册与白名单体验配额 */
export interface IPhoneAuthModule {
  getStatus(): PhoneAuthStatus;
  isPhoneRegistered(): boolean;
  /** 体验模式：已注册 + 白名单 + 今日有余量 */
  canUseExperience(): boolean;
  /** 自带 Key 模式：仅需完成手机号注册 */
  canUseByok(): boolean;
  registerPhone(phoneNumber: string): Promise<boolean>;
  refreshStatus(): Promise<boolean>;
  /** 体验模式每次完整自测前扣减 1 次（服务端计数） */
  consumeQuota(): Promise<boolean>;
  getAuthToken(): string;
}

/** 文案生成请求 */
export interface TextGenerationRequest {
  features: FaceAppearanceFeature;
  ancientEntries: AncientTextEntry[];
  profile?: UserProfile;
}

/** 文案生成响应 */
export interface TextGenerationResponse {
  culturalInterpretation: string;
  formattedReferences: AncientTextEntry[];
  success: boolean;
  usedOfflineFallback: boolean;
}
