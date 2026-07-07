/**
 * 相机扫描页
 * 按鸿蒙官方 CameraKit 预览流程：XComponent.onLoad → setSurfaceRect → surfaceId → 延迟启动
 */
import { display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppBootstrap, AppState } from '../common/AppBootstrap';
import { ModuleRegistry } from '../common/ModuleRegistry';
import { ModelType, ModelUsageMode, NetworkAuthLevel, UserProfile, CapturedImage } from '../common/types/AppTypes';
import { NavigationHelper } from '../common/utils/NavigationHelper';
import { NetworkAuthDialog } from '../components/NetworkAuthDialog';
import { ExperienceServerConfig } from '../common/constants/AppConstants';
import { ImageBrightnessUtil, LIGHT_BLOCK_THRESHOLD, LIGHT_WARN_THRESHOLD } from '../common/utils/ImageBrightnessUtil';
import { GalleryImagePickerUtil } from '../common/utils/GalleryImagePickerUtil';
import {
  FACE_GUIDE_OVAL_ASPECT,
  FACE_GUIDE_OVAL_TOP_MARGIN_VP,
  FACE_GUIDE_OVAL_WIDTH_RATIO,
  FaceGuideCropSpec,
  PortraitCropUtil
} from '../common/utils/PortraitCropUtil';

/** 联网授权后继续的分析来源 */
type AnalysisSource = 'capture' | 'gallery' | 'none';

@Entry
@Component
struct ScanPage {
  @State cameraReady: boolean = false;
  @State lightWarning: boolean = false;
  @State analyzing: boolean = false;
  @State statusText: string = '正在启动相机...';
  @State visionEngineLabel: string = '初始化中...';
  @State usingFrontCamera: boolean = true;
  /** 正在打开相机会话（显示加载遮罩） */
  @State cameraStarting: boolean = false;
  /** 权限通过后显示 XComponent */
  @State showPreview: boolean = false;
  /** 人像远近：0=远，1=近（默认略近，便于满屏采集） */
  @State zoomSliderValue: number = 0.55;
  /** 不支持镜头变焦时，用预览视觉缩放（仅对齐辅助） */
  @State previewVisualScale: number = 1.0;
  @State zoomSupported: boolean = false;
  /** 采集阶段：ready 待拍 | capturing 连拍中 | captured 已成功 | analyzing 分析中 */
  @State captureStage: string = 'ready';

  /** 双指捏合起始值 */
  private pinchBaseZoom: number = 0.55;

  private xComponentController: XComponentController = new XComponentController();
  private uiContext: UIContext = this.getUIContext();
  private surfaceId: string = '';
  private permissionGranted: boolean = false;
  private contextBound: boolean = false;
  private viewWidthPx: number = 0;
  private viewHeightPx: number = 0;
  private previewStarted: boolean = false;
  private initScheduled: boolean = false;
  private frameStartTimeoutId: number = -1;
  /** 联网授权弹窗关闭后继续的分析来源 */
  private pendingAnalysisSource: AnalysisSource = 'none';

  networkDialogController: CustomDialogController = new CustomDialogController({
    builder: NetworkAuthDialog({
      onSelect: (level: NetworkAuthLevel) => {
        this.handleScanNetworkAuth(level);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  async aboutToAppear(): Promise<void> {
    const hostContext = this.uiContext.getHostContext() as common.UIAbilityContext;
    await AppBootstrap.initialize(hostContext);
    this.visionEngineLabel = ModuleRegistry.getVision().getActiveEngineLabel();
    await this.requestPermissionAndBind();
  }

  onPageShow(): void {
    if (this.permissionGranted && this.contextBound && this.surfaceId.length > 0 && !this.previewStarted) {
      this.scheduleCameraInit(300);
    }
  }

  onPageHide(): void {
    this.clearFrameStartTimeout();
    const camera = ModuleRegistry.getCamera();
    camera.destroyImageData();
    camera.closeCamera();
    this.previewStarted = false;
    this.cameraReady = false;
    this.cameraStarting = false;
    this.initScheduled = false;
    this.captureStage = 'ready';
  }

  async aboutToDisappear(): Promise<void> {
    this.onPageHide();
  }

  clearFrameStartTimeout(): void {
    if (this.frameStartTimeoutId >= 0) {
      clearTimeout(this.frameStartTimeoutId);
      this.frameStartTimeoutId = -1;
    }
  }

  /** 申请相机权限（不在此处启动相机） */
  async requestPermissionAndBind(): Promise<void> {
    const permission = ModuleRegistry.getPermission();
    const result = await permission.requestCameraPermission();
    if (!result.granted) {
      this.statusText = '相机权限未授予，请在系统设置中开启后重试';
      return;
    }

    this.permissionGranted = true;
    const hostContext = this.uiContext.getHostContext() as common.UIAbilityContext;
    ModuleRegistry.getCamera().bindContext(hostContext);
    this.contextBound = true;
    this.statusText = '相机权限已获取，正在加载预览...';
    this.showPreview = true;
  }

  /** 官方顺序：先 setXComponentSurfaceRect，再 getXComponentSurfaceId */
  bindSurfaceWithRect(widthPx: number, heightPx: number): string {
    this.xComponentController.setXComponentSurfaceRect({
      offsetX: 0,
      offsetY: 0,
      surfaceWidth: widthPx,
      surfaceHeight: heightPx
    });
    return this.xComponentController.getXComponentSurfaceId();
  }

  scheduleCameraInit(delayMs: number): void {
    if (this.initScheduled || this.previewStarted || this.cameraStarting || !this.permissionGranted) {
      return;
    }
    if (this.surfaceId.length === 0) {
      return;
    }
    this.initScheduled = true;
    setTimeout(() => {
      this.initScheduled = false;
      this.tryStartPreview();
    }, delayMs);
  }

  /** 预览就绪：session.start 成功即可；frameStart 仅作补充 */
  markCameraReady(): void {
    if (this.cameraReady) {
      return;
    }
    this.clearFrameStartTimeout();
    this.cameraReady = true;
    this.refreshZoomCapability();
    if (this.usingFrontCamera) {
      this.captureStage = 'ready';
      this.statusText = '对准椭圆后，点右下角拍摄';
    } else {
      this.statusText = '后置镜头：请用屏幕侧对准面部';
    }
  }

  /** 相机就绪后读取变焦能力并应用默认远近 */
  refreshZoomCapability(): void {
    const camera = ModuleRegistry.getCamera();
    this.zoomSupported = camera.isZoomSupported();
    this.applyZoomFromSlider(this.zoomSliderValue);
  }

  clampZoomSlider(value: number): number {
    return Math.max(0, Math.min(1, value));
  }

  /**
   * 滑条/捏合 → 人像远近
   * 支持变焦：调镜头；不支持：调预览视觉缩放（拍照仍为全画面，请靠物理距离配合椭圆框）
   */
  applyZoomFromSlider(value: number): void {
    this.zoomSliderValue = this.clampZoomSlider(value);
    const camera = ModuleRegistry.getCamera();
    if (camera.isZoomSupported()) {
      const range = camera.getZoomRatioRange();
      const ratio = range.min + this.zoomSliderValue * (range.max - range.min);
      camera.setZoomRatio(ratio);
      this.previewVisualScale = 1.0;
    } else {
      // 0.88（远）～ 1.55（近）
      this.previewVisualScale = 0.88 + this.zoomSliderValue * 0.67;
    }
  }

  onPreviewFrameStarted(): void {
    console.info('[ScanPage] 预览首帧回调');
    this.markCameraReady();
  }

  onPreviewFrameTimeout(): void {
    // 部分机型不触发 frameStart，但预览已正常，仍标记就绪
    if (!this.cameraReady && this.previewStarted) {
      console.warn('[ScanPage] frameStart 未触发，按 session 成功处理');
      this.markCameraReady();
    }
  }

  async tryStartPreview(): Promise<void> {
    if (this.cameraStarting || this.previewStarted || !this.permissionGranted || !this.contextBound) {
      return;
    }
    if (this.surfaceId.length === 0) {
      this.statusText = 'Surface 未就绪，请稍候';
      return;
    }

    this.cameraStarting = true;
    this.cameraReady = false;
    this.statusText = '正在打开相机预览...';

    const viewW = this.viewWidthPx > 0 ? this.viewWidthPx : this.estimatePreviewWidthPx();
    const viewH = this.viewHeightPx > 0 ? this.viewHeightPx : this.estimatePreviewHeightPx();

    const camera = ModuleRegistry.getCamera();
    const opened = await camera.openCamera(this.surfaceId, viewW, viewH, () => {
      this.onPreviewFrameStarted();
    });

    this.cameraStarting = false;
    this.previewStarted = opened;

    if (opened) {
      this.usingFrontCamera = camera.isUsingFrontCamera();
      // 会话启动成功即关闭加载态（不依赖 frameStart，部分真机不回调）
      this.markCameraReady();
      this.frameStartTimeoutId = setTimeout(() => {
        this.onPreviewFrameTimeout();
      }, 1500);
    } else {
      this.statusText = '相机预览启动失败，请点击「重试预览」';
    }
  }

  estimatePreviewWidthPx(): number {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      return Math.round(displayInfo.width * 0.9);
    } catch (err) {
      console.warn('[ScanPage] 获取屏幕宽度失败', JSON.stringify(err));
      return 720;
    }
  }

  estimatePreviewHeightPx(): number {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      return Math.round(displayInfo.height * 0.92);
    } catch (err) {
      console.warn('[ScanPage] 获取屏幕高度失败', JSON.stringify(err));
      return Math.round(this.uiContext.vp2px(640));
    }
  }

  /** 区域尺寸就绪后配置 Surface 并调度相机 */
  onPreviewAreaReady(widthPx: number, heightPx: number): void {
    if (widthPx <= 0 || heightPx <= 0 || this.previewStarted) {
      return;
    }
    this.viewWidthPx = widthPx;
    this.viewHeightPx = heightPx;
    this.surfaceId = this.bindSurfaceWithRect(widthPx, heightPx);
    console.info(`[ScanPage] Surface 绑定 width=${widthPx} height=${heightPx} idLen=${this.surfaceId.length}`);
    if (!this.previewStarted && this.permissionGranted) {
      this.scheduleCameraInit(500);
    }
  }

  async retryPreview(): Promise<void> {
    this.clearFrameStartTimeout();
    await ModuleRegistry.getCamera().closeCamera();
    this.previewStarted = false;
    this.cameraReady = false;
    this.cameraStarting = false;
    this.initScheduled = false;
    this.xComponentController = new XComponentController();
    if (this.viewWidthPx > 0 && this.viewHeightPx > 0) {
      this.surfaceId = this.bindSurfaceWithRect(this.viewWidthPx, this.viewHeightPx);
      this.scheduleCameraInit(500);
    } else {
      this.surfaceId = '';
      this.statusText = '正在重新加载预览...';
    }
  }

  /** 需要联网授权时拍照前弹窗（体验模式或自带 Key 模式） */
  needsNetworkAuthBeforeCapture(): boolean {
    const config = ModuleRegistry.getModelConfig().getConfig();
    const phoneAuth = ModuleRegistry.getPhoneAuth();

    if (config.usageMode === ModelUsageMode.EXPERIENCE) {
      if (!phoneAuth.canUseExperience()) {
        return false;
      }
    } else {
      const token = config.apiKey.length > 0
        ? config.apiKey
        : (config.modelType === ModelType.PRIVATE ? config.privateToken : '');
      if (config.apiEndpoint.length === 0 || token.length === 0) {
        return false;
      }
      if (!phoneAuth.canUseByok()) {
        return false;
      }
    }

    if (AppState.networkAuthModule === null) {
      return false;
    }
    return !AppState.networkAuthModule.canUseNetwork();
  }

  /** 拍照前业务校验 */
  async validateBeforeCapture(): Promise<string | null> {
    const phoneAuth = ModuleRegistry.getPhoneAuth();
    if (!phoneAuth.isPhoneRegistered()) {
      return '请先在设置中注册手机号';
    }

    const config = ModuleRegistry.getModelConfig().getConfig();
    if (config.usageMode === ModelUsageMode.EXPERIENCE) {
      await phoneAuth.refreshStatus();
      if (!phoneAuth.canUseExperience()) {
        const status = phoneAuth.getStatus();
        if (!status.isWhitelisted) {
          return '您的手机号尚未加入白名单，请联系开发者或切换自带 Key';
        }
        return `今日免费次数已用完（${ExperienceServerConfig.DAILY_FREE_LIMIT} 次/天），请明日再试或切换自带 Key`;
      }
    } else if (!phoneAuth.canUseByok()) {
      return '请先完成手机号注册';
    }
    return null;
  }

  async handleScanNetworkAuth(level: NetworkAuthLevel): Promise<void> {
    if (AppState.networkAuthModule === null) {
      return;
    }

    if (level !== NetworkAuthLevel.DENY) {
      const permission = ModuleRegistry.getPermission();
      const result = await permission.requestNetworkPermission();
      if (!result.granted) {
        this.statusText = '网络权限未授予，将使用本地规则分析';
        await AppState.networkAuthModule.saveAuthLevel(NetworkAuthLevel.DENY);
      } else {
        await AppState.networkAuthModule.saveAuthLevel(level);
      }
    } else {
      this.statusText = '已拒绝联网，将使用本地规则分析';
      await AppState.networkAuthModule.saveAuthLevel(level);
    }

    this.visionEngineLabel = ModuleRegistry.getVision().getActiveEngineLabel();

    if (this.pendingAnalysisSource === 'capture') {
      this.pendingAnalysisSource = 'none';
      await this.doCaptureAndAnalyze();
    } else if (this.pendingAnalysisSource === 'gallery') {
      this.pendingAnalysisSource = 'none';
      await this.doGalleryPickAndAnalyze();
    }
  }

  /** 拍照或上传前统一校验与联网授权 */
  async beginAnalysis(source: AnalysisSource): Promise<void> {
    if (this.analyzing) {
      return;
    }
    if (source === 'capture' && !this.cameraReady) {
      return;
    }

    const validateMsg = await this.validateBeforeCapture();
    if (validateMsg !== null) {
      this.statusText = validateMsg;
      return;
    }

    if (this.needsNetworkAuthBeforeCapture()) {
      this.pendingAnalysisSource = source;
      this.networkDialogController.open();
      return;
    }

    if (source === 'capture') {
      await this.doCaptureAndAnalyze();
    } else {
      await this.doGalleryPickAndAnalyze();
    }
  }

  async captureAndAnalyze(): Promise<void> {
    await this.beginAnalysis('capture');
  }

  async galleryPickAndAnalyze(): Promise<void> {
    await this.beginAnalysis('gallery');
  }

  /** 对已有图像执行亮度检测与色诊分析（拍照与相册共用） */
  async analyzeCapturedImage(captured: CapturedImage | null, emptyMessage: string): Promise<void> {
    if (captured === null || captured.data.byteLength === 0) {
      this.statusText = emptyMessage;
      return;
    }

    if (AppState.orchestrator === null) {
      this.statusText = '分析服务未就绪，请返回首页重试';
      return;
    }

    // 用本地像素实测亮度，不用 AI 返回值（云端常误报光线不足）
    const localBrightness = await ImageBrightnessUtil.measure(captured);
    console.info(`[ScanPage] 本地亮度=${localBrightness.toFixed(1)}`);
    if (localBrightness < LIGHT_BLOCK_THRESHOLD) {
      this.lightWarning = true;
      this.statusText = '光线不足或画面过暗，请换一张更明亮的照片或移至明亮处重拍';
      return;
    }
    this.lightWarning = localBrightness < LIGHT_WARN_THRESHOLD;

    let profile: UserProfile | undefined = undefined;
    if (AppState.settingsModule !== null) {
      profile = await AppState.settingsModule.getUserProfile();
    }

    const report = await AppState.orchestrator.runDiagnosis(captured, profile, localBrightness);
    AppState.currentReport = report;
    NavigationHelper.push(this.uiContext, 'pages/ReportPage');
  }

  async doGalleryPickAndAnalyze(): Promise<void> {
    if (this.analyzing) {
      return;
    }

    this.analyzing = true;
    this.lightWarning = false;
    this.captureStage = 'analyzing';
    this.statusText = '请选择相册中的正脸照片...';

    try {
      const picked = await GalleryImagePickerUtil.pickPortraitImage();
      if (picked === null) {
        this.captureStage = 'ready';
        this.statusText = '未选择照片，可继续拍照或重新上传';
        return;
      }

      this.statusText = '正在分析所选照片，请稍候...';
      await this.analyzeCapturedImage(picked, '未能读取所选照片，请换一张重试');
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      this.captureStage = 'ready';
      this.statusText = msg.length > 0 ? msg : '分析过程出现异常，请重试';
      console.error('[ScanPage] 相册分析失败', JSON.stringify(err));
    } finally {
      this.analyzing = false;
      if (this.captureStage !== 'ready') {
        this.captureStage = 'ready';
      }
    }
  }

  /** 与椭圆 UI 一致的裁切参数（拍照后只上传头像区域） */
  buildFaceGuideCropSpec(): FaceGuideCropSpec {
    const viewW = this.viewWidthPx > 0 ? this.viewWidthPx : this.estimatePreviewWidthPx();
    const viewH = this.viewHeightPx > 0 ? this.viewHeightPx : this.estimatePreviewHeightPx();
    return {
      viewWidthPx: viewW,
      viewHeightPx: viewH,
      ovalWidthRatio: FACE_GUIDE_OVAL_WIDTH_RATIO,
      ovalAspect: FACE_GUIDE_OVAL_ASPECT,
      ovalTopMarginPx: Math.round(this.uiContext.vp2px(FACE_GUIDE_OVAL_TOP_MARGIN_VP))
    };
  }

  /** 连拍选帧后裁切椭圆内头像，不上传全景 */
  async cropCapturedPortrait(captured: CapturedImage | null): Promise<CapturedImage | null> {
    if (captured === null) {
      return null;
    }
    const cropped = await PortraitCropUtil.cropToFaceGuide(captured, this.buildFaceGuideCropSpec());
    return cropped !== null ? cropped : captured;
  }

  /** 短暂停留，让用户看见「已采集」提示 */
  private delayMs(ms: number): Promise<void> {
    return new Promise<void>((resolve) => {
      setTimeout(resolve, ms);
    });
  }

  async doCaptureAndAnalyze(): Promise<void> {
    if (!this.cameraReady || this.analyzing) {
      return;
    }

    this.analyzing = true;
    this.lightWarning = false;
    this.captureStage = 'capturing';
    this.statusText = '采集中，请保持正脸不动…';

    try {
      const camera = ModuleRegistry.getCamera();
      const rawCaptured = await camera.captureBestPhoto();
      if (rawCaptured === null || rawCaptured.data.byteLength === 0) {
        this.captureStage = 'ready';
        this.statusText = '拍照失败，请保持面部在椭圆内后重试';
        return;
      }

      const captured = await this.cropCapturedPortrait(rawCaptured);
      if (captured === null || captured.data.byteLength === 0) {
        this.captureStage = 'ready';
        this.statusText = '头像裁切失败，请重试';
        return;
      }

      // 采集成功：底部显著提示「已采集」
      this.captureStage = 'captured';
      this.statusText = '头像已裁切完成';
      await this.delayMs(800);

      this.captureStage = 'analyzing';
      this.statusText = '正在分析，请稍候…';
      await this.analyzeCapturedImage(captured, '分析失败，请重试');
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      this.captureStage = 'ready';
      this.statusText = msg.length > 0 ? msg : '分析过程出现异常，请重试';
      console.error('[ScanPage] 分析失败', JSON.stringify(err));
    } finally {
      this.analyzing = false;
      if (this.captureStage !== 'ready') {
        this.captureStage = 'ready';
      }
    }
  }

  /** 底部唯一状态行（避免与预览区提示重叠） */
  @Builder
  BottomStatusLine() {
    if (this.captureStage === 'captured') {
      Text('✓ 已采集')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor('#A5D6A7')
        .textAlign(TextAlign.Center)
        .width('100%')
    } else if (this.captureStage === 'capturing') {
      Text('采集中，请保持正脸不动…')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFE082')
        .textAlign(TextAlign.Center)
        .width('100%')
    } else if (this.captureStage === 'analyzing') {
      Text('正在分析，请稍候…')
        .fontSize(16)
        .fontColor('#FFFFFFDD')
        .textAlign(TextAlign.Center)
        .width('100%')
    } else if (this.lightWarning) {
      Text('⚠ 光线偏暗，请移至明亮处')
        .fontSize(14)
        .fontColor('#FFE082')
        .textAlign(TextAlign.Center)
        .width('100%')
    } else if (!this.cameraReady && this.permissionGranted) {
      Text('预览未就绪，点此重试')
        .fontSize(14)
        .fontColor('#FFE082')
        .textAlign(TextAlign.Center)
        .width('100%')
        .onClick(() => {
          this.retryPreview();
        })
    } else if (this.cameraReady) {
      if (!this.usingFrontCamera) {
        Text('后置镜头：请用屏幕侧对准面部')
          .fontSize(13)
          .fontColor('#FFFFFFCC')
          .textAlign(TextAlign.Center)
          .width('100%')
      } else {
        Text('正脸对准椭圆 · 右侧按钮拍摄 · 仅上传框内头像')
          .fontSize(13)
          .fontColor('#FFFFFFCC')
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    } else {
      Text(this.statusText)
        .fontSize(13)
        .fontColor('#FFFFFFCC')
        .textAlign(TextAlign.Center)
        .width('100%')
    }
  }

  /** 底部控制区：提示 + 变焦 + 左右按钮（全部在屏幕下方） */
  @Builder
  BottomControlPanel() {
    Column({ space: 10 }) {
      this.BottomStatusLine()

      Row() {
        Text('远')
          .fontSize(12)
          .fontColor('#FFFFFFAA')
          .width(24)
        Slider({
          value: this.zoomSliderValue,
          min: 0,
          max: 1,
          step: 0.02,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .blockColor(Color.White)
          .trackColor('#FFFFFF33')
          .selectedColor(Color.White)
          .enabled(!this.analyzing)
          .onChange((value: number) => {
            this.applyZoomFromSlider(value);
          })
        Text('近')
          .fontSize(12)
          .fontColor('#FFFFFFAA')
          .width(24)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 左下相册 · 右下拍摄（贴屏幕底边两侧）
      Row() {
        Column() {
          Button(this.analyzing ? '…' : '相册')
            .width(64)
            .height(64)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#5C3D2E')
            .borderRadius(32)
            .backgroundColor(this.analyzing ? '#FFE08266' : '#FFE082')
            .enabled(!this.analyzing)
            .onClick(() => this.galleryPickAndAnalyze())
          Text('相册')
            .fontSize(11)
            .fontColor('#FFE082')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Center)

        Blank().layoutWeight(1)

        Column() {
          this.ShutterButton()
          Text('拍摄')
            .fontSize(11)
            .fontColor('#FFFFFFCC')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 24 })
    .backgroundColor('#CC000000')
  }

  /** 竖向椭圆宽度（窄边，占屏宽百分比） */
  getFrameWidthPercent(): string {
    return `${Math.round(FACE_GUIDE_OVAL_WIDTH_RATIO * 100)}%`;
  }

  /** 宽高比 width/height，小于 1 即为竖立椭圆 */
  getOvalAspectRatio(): number {
    return FACE_GUIDE_OVAL_ASPECT;
  }

  /** 圆形拍摄按钮（手动按下才开始连拍，不自动拍照） */
  @Builder
  ShutterButton() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(76)
        .height(76)
        .border({ width: 4, color: '#FFFFFFDD' })
        .borderRadius(38)
        .backgroundColor('#FFFFFF00')

      Column()
        .width(this.analyzing ? 62 : 66)
        .height(this.analyzing ? 62 : 66)
        .borderRadius(33)
        .backgroundColor(this.analyzing ? '#FFFFFF66' : Color.White)
    }
    .width(84)
    .height(84)
    .opacity(this.cameraReady && !this.analyzing ? 1 : 0.45)
    .onClick(() => {
      if (!this.analyzing && this.cameraReady) {
        this.captureAndAnalyze();
      }
    })
  }

  /** 竖向椭圆 + 虚线中轴对准框 */
  @Builder
  FaceGuideOval() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .border({ width: 3, color: '#FFFFFFCC' })
        .borderRadius('50%')

      // 颜面正中虚线（额—鼻—颏中轴）
      Column()
        .width(2)
        .height('92%')
        .border({
          width: { left: 2, right: 0, top: 0, bottom: 0 },
          color: { left: '#FFFFFFAA' },
          style: { left: BorderStyle.Dashed }
        })
    }
    .width(this.getFrameWidthPercent())
    .aspectRatio(this.getOvalAspectRatio())
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 第一层：满屏相机预览 + 椭圆参考框
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.showPreview) {
          XComponent({
            id: 'cameraPreviewSurface',
            type: XComponentType.SURFACE,
            libraryname: '',
            controller: this.xComponentController
          })
            .width('100%')
            .height('100%')
            .scale({ x: this.previewVisualScale, y: this.previewVisualScale })
            .onAreaChange((_oldValue: Area, newValue: Area) => {
              const widthPx = Math.round(this.uiContext.vp2px(Number(newValue.width)));
              const heightPx = Math.round(this.uiContext.vp2px(Number(newValue.height)));
              this.onPreviewAreaReady(widthPx, heightPx);
            })
            .onLoad(() => {
              console.info('[ScanPage] XComponent onLoad');
              if (this.viewWidthPx > 0 && this.viewHeightPx > 0) {
                this.onPreviewAreaReady(this.viewWidthPx, this.viewHeightPx);
              } else {
                this.onPreviewAreaReady(this.estimatePreviewWidthPx(), this.estimatePreviewHeightPx());
              }
            })
        } else {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#000000')
        }

        // 竖立椭圆 + 虚线中轴，偏上居中
        Column() {
          this.FaceGuideOval()
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ top: FACE_GUIDE_OVAL_TOP_MARGIN_VP })

        if (this.cameraStarting) {
          Column({ space: 8 }) {
            Text('正在打开相机…')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#00000066')
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .height('100%')
      .gesture(
        PinchGesture({ fingers: 2, distance: 1 })
          .onActionStart(() => {
            this.pinchBaseZoom = this.zoomSliderValue;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (event.scale > 0) {
              const next = this.pinchBaseZoom + (event.scale - 1) * 0.35;
              this.applyZoomFromSlider(next);
            }
          })
      )

      // 顶部导航（半透明）
      Row() {
        Text('←')
          .fontSize(24)
          .fontColor(Color.White)
          .onClick(() => NavigationHelper.back(this.uiContext))
        Text('古籍面诊自测')
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(24)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 8 })
      .backgroundColor('#00000055')

      // 全部操作与提示集中在底部，避免与预览区重叠
      Column() {
        this.BottomControlPanel()
      }
      .width('100%')
      .align(Alignment.Bottom)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}
