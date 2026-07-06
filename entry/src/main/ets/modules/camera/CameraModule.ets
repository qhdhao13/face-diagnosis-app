/**
 * 模块2：相机采集模块
 * 封装 CameraKit，图像仅内存缓存，分析后立即销毁
 */
import { common } from '@kit.AbilityKit';
import { CapturedImage, ICameraModule, PreviewSize, ZoomRatioRange } from '../../common/types/AppTypes';
import { CameraSessionManager } from './CameraSessionManager';

export class CameraModule implements ICameraModule {
  private sessionManager: CameraSessionManager | null = null;
  private lastImage: CapturedImage | null = null;

  /** 绑定 UIAbility 上下文 */
  bindContext(context: Object): void {
    this.sessionManager = new CameraSessionManager(context as common.UIAbilityContext);
  }

  /** 打开前置摄像头并绑定预览 Surface */
  async openCamera(
    surfaceId: string,
    viewWidthPx: number = 720,
    viewHeightPx: number = 960,
    onPreviewFrameStart?: () => void
  ): Promise<boolean> {
    if (this.sessionManager === null) {
      console.error('[CameraModule] 未绑定上下文');
      return false;
    }
    return await this.sessionManager.startPreview(surfaceId, viewWidthPx, viewHeightPx, onPreviewFrameStart);
  }

  /** 拍照并缓存到内存（不写磁盘、不入相册） */
  async capturePhoto(): Promise<CapturedImage | null> {
    if (this.sessionManager === null) {
      return null;
    }
    this.lastImage = await this.sessionManager.takePhoto();
    return this.lastImage;
  }

  /** 分析完成后立即销毁内存图像 */
  destroyImageData(): void {
    this.lastImage = null;
  }

  /** 获取当前环境光线水平（0-1） */
  getLightLevel(): number {
    if (this.sessionManager === null) {
      return 0.7;
    }
    return this.sessionManager.getLightLevel();
  }

  /** 由视觉模块回写亮度，用于 UI 光线提示 */
  updateLightLevel(brightness: number): void {
    this.sessionManager?.updateLightLevel(brightness);
  }

  /** 关闭相机释放资源 */
  async closeCamera(): Promise<void> {
    this.destroyImageData();
    if (this.sessionManager !== null) {
      await this.sessionManager.release();
    }
  }

  isUsingFrontCamera(): boolean {
    if (this.sessionManager === null) {
      return true;
    }
    return this.sessionManager.isFrontCameraActive();
  }

  getPreviewSize(): PreviewSize {
    if (this.sessionManager === null) {
      return { width: 0, height: 0 };
    }
    return this.sessionManager.getPreviewSize();
  }

  isZoomSupported(): boolean {
    if (this.sessionManager === null) {
      return false;
    }
    return this.sessionManager.isZoomSupported();
  }

  getZoomRatioRange(): ZoomRatioRange {
    if (this.sessionManager === null) {
      return { min: 1, max: 1 };
    }
    return this.sessionManager.getZoomRatioRange();
  }

  setZoomRatio(ratio: number): void {
    this.sessionManager?.setZoomRatio(ratio);
  }
}
