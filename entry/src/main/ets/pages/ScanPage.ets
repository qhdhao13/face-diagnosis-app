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
  /** 人像远近：0=远，1=近（映射到镜头变焦或预览缩放） */
  @State zoomSliderValue: number = 0.4;
  /** 不支持镜头变焦时，用预览视觉缩放（仅对齐辅助） */
  @State previewVisualScale: number = 1.0;
  @State zoomSupported: boolean = false;

  /** 固定椭圆取景框（仅作对准参考，不随滑条变化） */
  private readonly FRAME_WIDTH: number = 285;
  private readonly FRAME_HEIGHT: number = 360;
  /** 双指捏合起始值 */
  private pinchBaseZoom: number = 0.4;

  private previewProfileWidth: number = 1280;
  private previewProfileHeight: number = 720;

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
      this.statusText = '椭圆框固定作对准参考；拖动滑条或双指捏合，调节人像远近';
    } else {
      this.statusText = '当前为后置摄像头，请翻转手机用屏幕侧对准面部';
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
    return Math.round(this.uiContext.vp2px(400));
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
    this.statusText = '请选择相册中的正脸照片...';

    try {
      const picked = await GalleryImagePickerUtil.pickPortraitImage();
      if (picked === null) {
        this.statusText = '未选择照片，可继续拍照或重新上传';
        return;
      }

      this.statusText = '正在分析所选照片，请稍候...';
      await this.analyzeCapturedImage(picked, '未能读取所选照片，请换一张重试');
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      this.statusText = msg.length > 0 ? msg : '分析过程出现异常，请重试';
      console.error('[ScanPage] 相册分析失败', JSON.stringify(err));
    } finally {
      this.analyzing = false;
    }
  }

  async doCaptureAndAnalyze(): Promise<void> {
    if (!this.cameraReady || this.analyzing) {
      return;
    }

    this.analyzing = true;
    this.lightWarning = false;
    this.statusText = '正在拍照并分析，请稍候...';

    try {
      const camera = ModuleRegistry.getCamera();
      const captured = await camera.capturePhoto();
      await this.analyzeCapturedImage(captured, '拍照失败：未获取到图像数据，请保持面部在框内后重试');
    } catch (err) {
      const msg = err instanceof Error ? err.message : '';
      this.statusText = msg.length > 0 ? msg : '分析过程出现异常，请重试';
      console.error('[ScanPage] 分析失败', JSON.stringify(err));
    } finally {
      this.analyzing = false;
    }
  }

  getFrameWidth(): number {
    return this.FRAME_WIDTH;
  }

  getFrameHeight(): number {
    return this.FRAME_HEIGHT;
  }

  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(22)
          .fontColor($r('app.color.primary'))
          .onClick(() => NavigationHelper.back(this.uiContext))
        Text('古籍面诊自测')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        // 顶部常驻入口：小屏上底部按钮可能被挡住，此处始终可见
        Text(this.analyzing ? '…' : '上传照片')
          .fontSize(14)
          .fontColor(this.analyzing ? $r('app.color.text_secondary') : $r('app.color.primary'))
          .fontWeight(FontWeight.Medium)
          .width(56)
          .textAlign(TextAlign.End)
          .onClick(() => {
            if (!this.analyzing) {
              this.galleryPickAndAnalyze();
            }
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })

      Scroll() {
        Column() {
      // 拍摄提示：距离与光线（固定展示，帮助用户一次拍准）
      Column({ space: 4 }) {
        Text('拍摄提示')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
          .width('100%')
        Text('最佳距离：约 40–60 厘米，正脸对准椭圆框，额、颧、颏居中、无遮挡')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
        Text('拍摄光线：明亮均匀的自然光或室内顶灯，避免逆光、强阴影与重度美颜滤镜')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }
      .width('90%')
      .alignItems(HorizontalAlign.Start)
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.primary_light'))
      .borderRadius(10)
      .margin({ bottom: 8 })

      Stack({ alignContent: Alignment.Center }) {
        if (this.showPreview) {
          XComponent({
            id: 'cameraPreviewSurface',
            type: XComponentType.SURFACE,
            libraryname: '',
            controller: this.xComponentController
          })
            // 官方：竖屏显示时 XComponent 宽高与 preview 流宽高对调
            .width(this.uiContext.px2vp(this.previewProfileHeight))
            .height(this.uiContext.px2vp(this.previewProfileWidth))
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

        Column()
          .width(this.getFrameWidth())
          .height(this.getFrameHeight())
          .border({ width: 2, color: '#FFFFFFAA' })
          .borderRadius(this.getFrameWidth() / 2)

        if (this.cameraReady && !this.usingFrontCamera) {
          Text('后置镜头：请用屏幕这一面对准面部')
            .fontSize(12)
            .fontColor('#FFD700')
            .backgroundColor('#000000AA')
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(8)
            .position({ x: '50%', y: 12 })
            .markAnchor({ x: '50%', y: 0 })
        }

        if (this.lightWarning) {
          Text('⚠ 光线不足，请换至明亮环境')
            .fontSize(13)
            .fontColor('#FFD700')
            .backgroundColor('#000000AA')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(8)
            .position({ x: '50%', y: 16 })
            .markAnchor({ x: '50%', y: 0 })
        }

        if (this.cameraStarting) {
          Column() {
            Text('正在打开相机...')
              .fontSize(15)
              .fontColor(Color.White)
          }
          .width('100%')
          .height('100%')
          .backgroundColor('#00000055')
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('90%')
      .height(400)
      .borderRadius(16)
      .backgroundColor('#000000')
      .margin({ bottom: 8 })
      .gesture(
        PinchGesture({ fingers: 2, distance: 1 })
          .onActionStart(() => {
            this.pinchBaseZoom = this.zoomSliderValue;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (event.scale > 0) {
              // 捏合放大 → 数值增大 → 人像更近
              const next = this.pinchBaseZoom + (event.scale - 1) * 0.35;
              this.applyZoomFromSlider(next);
            }
          })
      )

      Row() {
        Text('远')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width(24)
        Slider({
          value: this.zoomSliderValue,
          min: 0,
          max: 1,
          step: 0.02,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .blockColor($r('app.color.primary'))
          .trackColor($r('app.color.divider'))
          .selectedColor($r('app.color.primary'))
          .onChange((value: number) => {
            this.applyZoomFromSlider(value);
          })
        Text('近')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width(24)
          .textAlign(TextAlign.End)
      }
      .width('90%')
      .padding({ left: 8, right: 8, bottom: 8 })

      Text(this.zoomSupported
        ? '椭圆框固定不变；滑条/双指仅调节人像远近（镜头变焦）'
        : '椭圆框固定不变；滑条/双指调节预览大小辅助对齐（本机不支持镜头变焦，请配合前后距离）')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 12 })
        .padding({ left: 24, right: 24 })

      Text(this.statusText)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 12 })
        .padding({ left: 24, right: 24 })

      // 拍照与上传并列，避免上传按钮被挤到屏幕外
      Row({ space: 12 }) {
        Button(this.analyzing ? '分析中...' : '现场拍照')
          .layoutWeight(1)
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .borderRadius(24)
          .backgroundColor(this.analyzing ? $r('app.color.divider') : $r('app.color.primary'))
          .enabled(!this.analyzing && this.cameraReady)
          .onClick(() => this.captureAndAnalyze())

        Button(this.analyzing ? '处理中...' : '上传已有照片')
          .layoutWeight(1)
          .height(48)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .borderRadius(24)
          .backgroundColor($r('app.color.primary_light'))
          .fontColor($r('app.color.text_primary'))
          .enabled(!this.analyzing)
          .onClick(() => this.galleryPickAndAnalyze())
      }
      .width('90%')
      .margin({ bottom: 8 })

      Text('上传：从相册选已拍好的正脸；拍照：使用上方取景框现场拍摄')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 8 })
        .padding({ left: 24, right: 24 })

      if (!this.cameraReady && this.permissionGranted) {
        Button('重试预览')
          .fontSize(14)
          .height(40)
          .margin({ bottom: 12 })
          .backgroundColor($r('app.color.primary_light'))
          .onClick(() => {
            this.retryPreview();
          })
      }

      Text('拍照或上传后将提交至云端 AI 分析气色，完成后本地立即删除；断网时使用本地规则兜底')
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ bottom: 8 })

      Text(`分析引擎：${this.visionEngineLabel}`)
        .fontSize(10)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ bottom: 24 })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
