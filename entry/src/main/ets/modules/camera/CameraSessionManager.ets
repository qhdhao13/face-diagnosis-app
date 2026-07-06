/**
 * CameraKit 会话管理
 * 负责前置摄像头预览、拍照、资源释放（图像仅内存，不写磁盘）
 */
import { camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { display } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { CapturedImage, PreviewSize, ZoomRatioRange } from '../../common/types/AppTypes';

/** 拍照完成回调类型 */
type CaptureFinishCallback = (result: CapturedImage | null) => void;
/** 预览首帧回调 */
type PreviewFrameStartCallback = () => void;

export class CameraSessionManager {
  private context: common.UIAbilityContext;
  private cameraManager: camera.CameraManager | null = null;
  private cameraInput: camera.CameraInput | null = null;
  private previewOutput: camera.PreviewOutput | null = null;
  private photoOutput: camera.PhotoOutput | null = null;
  private session: camera.PhotoSession | null = null;
  private lightLevel: number = 0.7;
  private captureFinish: CaptureFinishCallback | null = null;
  private previewFrameStart: PreviewFrameStartCallback | null = null;
  private captureTimeoutId: number = -1;
  private isRunning: boolean = false;
  private useFrontCamera: boolean = true;
  private previewWidth: number = 0;
  private previewHeight: number = 0;
  private frameStartNotified: boolean = false;
  private zoomRatio: number = 1.0;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  isFrontCameraActive(): boolean {
    return this.useFrontCamera;
  }

  getPreviewSize(): PreviewSize {
    return { width: this.previewWidth, height: this.previewHeight };
  }

  /** 启动前置摄像头预览 */
  async startPreview(
    surfaceId: string,
    viewWidthPx: number,
    viewHeightPx: number,
    onPreviewFrameStart?: PreviewFrameStartCallback
  ): Promise<boolean> {
    if (surfaceId.length === 0) {
      console.error('[CameraSession] surfaceId 为空');
      return false;
    }

    this.previewFrameStart = onPreviewFrameStart ?? null;
    this.frameStartNotified = false;

    try {
      await this.release();
      this.cameraManager = camera.getCameraManager(this.context);
      const devices = this.cameraManager.getSupportedCameras();
      if (devices.length === 0) {
        console.error('[CameraSession] 未找到任何摄像头（模拟器可能不支持）');
        return false;
      }

      let targetDevice = devices.find(
        (dev: camera.CameraDevice) => dev.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT
      );
      this.useFrontCamera = targetDevice !== undefined;
      if (targetDevice === undefined) {
        targetDevice = devices[0];
        console.warn('[CameraSession] 未找到前置摄像头，回退默认摄像头');
      }

      this.cameraInput = this.cameraManager.createCameraInput(targetDevice);
      await this.cameraInput.open();

      const capability = this.cameraManager.getSupportedOutputCapability(
        targetDevice,
        camera.SceneMode.NORMAL_PHOTO
      );
      if (capability.previewProfiles.length === 0) {
        console.error('[CameraSession] 不支持预览');
        return false;
      }

      const viewRatio = viewWidthPx > 0 && viewHeightPx > 0
        ? viewWidthPx / viewHeightPx
        : 9 / 16;
      const previewProfile = CameraSessionManager.pickPreviewProfile(capability.previewProfiles, viewRatio);
      const photoProfile = capability.photoProfiles.length > 0
        ? CameraSessionManager.pickPhotoProfile(capability.photoProfiles, previewProfile)
        : previewProfile;

      this.previewWidth = previewProfile.size.width;
      this.previewHeight = previewProfile.size.height;

      this.previewOutput = this.cameraManager.createPreviewOutput(previewProfile, surfaceId);
      console.info(
        `[CameraSession] surfaceIdLen=${surfaceId.length}, view=${viewWidthPx}x${viewHeightPx}, ` +
        `profile=${previewProfile.size.width}x${previewProfile.size.height}`
      );

      CameraSessionManager.bindPreviewListeners(this.previewOutput, () => {
        if (this.frameStartNotified) {
          return;
        }
        this.frameStartNotified = true;
        if (this.previewFrameStart !== null) {
          this.previewFrameStart();
        }
      });

      this.photoOutput = this.cameraManager.createPhotoOutput(photoProfile);
      CameraSessionManager.enablePhotoMirrorIfSupported(this.photoOutput);
      console.info(
        `[CameraSession] photoProfile=${photoProfile.size.width}x${photoProfile.size.height}`
      );

      this.photoOutput.on('photoAvailable', (err: BusinessError, photo: camera.Photo) => {
        this.onPhotoAvailable(err, photo);
      });

      this.photoOutput.on('error', (error: BusinessError) => {
        console.error('[CameraSession] PhotoOutput 错误', JSON.stringify(error));
      });

      this.session = this.cameraManager.createSession(camera.SceneMode.NORMAL_PHOTO) as camera.PhotoSession;
      this.session.beginConfig();
      this.session.addInput(this.cameraInput);
      this.session.addOutput(this.previewOutput);
      this.session.addOutput(this.photoOutput);
      await this.session.commitConfig();
      await this.session.start();

      CameraSessionManager.applyPreviewRotation(this.previewOutput, this.useFrontCamera);
      CameraSessionManager.applyContinuousAutoFocus(this.session);
      CameraSessionManager.applyAutoExposure(this.session);
      this.zoomRatio = 1.0;

      this.isRunning = true;
      console.info('[CameraSession] session.start 成功');
      return true;
    } catch (err) {
      console.error('[CameraSession] 启动失败', JSON.stringify(err));
      await this.release();
      return false;
    }
  }

  private static bindPreviewListeners(
    previewOutput: camera.PreviewOutput,
    onFrameStart: () => void
  ): void {
    previewOutput.on('frameStart', (err: BusinessError) => {
      if (CameraSessionManager.isCallbackFailed(err)) {
        console.warn('[CameraSession] frameStart 错误', JSON.stringify(err));
        return;
      }
      console.info('[CameraSession] 预览首帧已开始');
      onFrameStart();
    });
    previewOutput.on('error', (previewError: BusinessError) => {
      console.error('[CameraSession] PreviewOutput 错误', JSON.stringify(previewError));
    });
  }

  /** 校正预览方向；前置镜头开启镜像 */
  private static applyPreviewRotation(previewOutput: camera.PreviewOutput, mirror: boolean): void {
    try {
      const displayRotation = display.getDefaultDisplaySync().rotation;
      const imageRotation = displayRotation * camera.ImageRotation.ROTATION_90;
      const previewRotation = previewOutput.getPreviewRotation(imageRotation);
      previewOutput.setPreviewRotation(previewRotation, mirror);
    } catch (err) {
      console.warn('[CameraSession] setPreviewRotation 失败', JSON.stringify(err));
    }
  }

  /** 前置拍照镜像（若设备支持） */
  private static enablePhotoMirrorIfSupported(photoOutput: camera.PhotoOutput): void {
    try {
      if (photoOutput.isMirrorSupported()) {
        photoOutput.enableMirror(true);
      }
    } catch (err) {
      console.warn('[CameraSession] enableMirror 失败', JSON.stringify(err));
    }
  }

  /** 获取拍照旋转角度（官方建议用 PhotoOutput.getPhotoRotation） */
  private getCaptureRotation(): camera.ImageRotation {
    if (this.photoOutput === null) {
      return camera.ImageRotation.ROTATION_0;
    }
    try {
      const displayRotation = display.getDefaultDisplaySync().rotation;
      const imageRotation = displayRotation * camera.ImageRotation.ROTATION_90;
      return this.photoOutput.getPhotoRotation(imageRotation);
    } catch (err) {
      console.warn('[CameraSession] getPhotoRotation 失败', JSON.stringify(err));
      return camera.ImageRotation.ROTATION_0;
    }
  }

  /** 拷贝 ArrayBuffer，避免底层 buffer 被 release 后失效 */
  private static copyBuffer(srcBuffer: ArrayBuffer): ArrayBuffer {
    const copiedBuffer: ArrayBuffer = new ArrayBuffer(srcBuffer.byteLength);
    new Uint8Array(copiedBuffer).set(new Uint8Array(srcBuffer));
    return copiedBuffer;
  }

  /**
   * 判断鸿蒙异步回调中的 err 是否表示失败
   * 注意：成功时 err 常为数字 0，不能写 err.code !== 0（数字没有 code 字段会被误判）
   */
  private static isCallbackFailed(err: BusinessError | number | undefined | null): boolean {
    if (err === undefined || err === null) {
      return false;
    }
    if (typeof err === 'number') {
      return err !== 0;
    }
    return err.code !== 0;
  }

  /** 连续自动对焦 */
  private static applyContinuousAutoFocus(session: camera.PhotoSession): void {
    try {
      if (session.isFocusModeSupported(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO)) {
        session.setFocusMode(camera.FocusMode.FOCUS_MODE_CONTINUOUS_AUTO);
      }
    } catch (err) {
      console.warn('[CameraSession] 自动对焦设置失败', JSON.stringify(err));
    }
  }

  /** 自动曝光 */
  private static applyAutoExposure(session: camera.PhotoSession): void {
    try {
      if (session.isExposureModeSupported(camera.ExposureMode.EXPOSURE_MODE_AUTO)) {
        session.setExposureMode(camera.ExposureMode.EXPOSURE_MODE_AUTO);
      }
    } catch (err) {
      console.warn('[CameraSession] 自动曝光设置失败', JSON.stringify(err));
    }
  }

  private isCapturing: boolean = false;

  async takePhoto(): Promise<CapturedImage | null> {
    if (!this.isRunning || this.photoOutput === null) {
      console.error('[CameraSession] takePhoto: 相机会话未运行');
      return null;
    }
    if (this.isCapturing) {
      console.warn('[CameraSession] 上一张仍在处理，请稍候');
      return null;
    }

    this.isCapturing = true;
    const result = await this.takePhotoOnce(false);
    if (result === null) {
      console.warn('[CameraSession] 首次拍照失败，关闭 mirror 重试一次');
      const retryResult = await this.takePhotoOnce(true);
      this.isCapturing = false;
      return retryResult;
    }
    this.isCapturing = false;
    return result;
  }

  private takePhotoOnce(disableMirror: boolean): Promise<CapturedImage | null> {
    return new Promise<CapturedImage | null>((resolve) => {
      this.clearCaptureTimeout();
      this.captureFinish = resolve;

      this.captureTimeoutId = setTimeout(() => {
        console.error('[CameraSession] 拍照超时（15s 无回调）');
        this.finishCapture(null);
      }, 15000);

      const settings: camera.PhotoCaptureSetting = {
        quality: camera.QualityLevel.QUALITY_LEVEL_HIGH,
        rotation: this.getCaptureRotation(),
        mirror: disableMirror ? false : this.useFrontCamera
      };

      console.info(
        `[CameraSession] 发起拍照 rotation=${settings.rotation} mirror=${settings.mirror}`
      );

      try {
        this.photoOutput!.capture(settings, (err: BusinessError) => {
          if (CameraSessionManager.isCallbackFailed(err)) {
            console.error('[CameraSession] capture 请求失败', JSON.stringify(err));
            this.finishCapture(null);
            return;
          }
          console.info('[CameraSession] capture 请求已接受，等待 photoAvailable');
        });
      } catch (err) {
        console.error('[CameraSession] 触发 capture 异常', JSON.stringify(err));
        this.finishCapture(null);
      }
    });
  }

  private onPhotoAvailable(err: BusinessError, photo: camera.Photo): void {
    if (this.captureFinish === null) {
      console.warn('[CameraSession] photoAvailable 忽略：无进行中的拍照请求');
      return;
    }

    if (CameraSessionManager.isCallbackFailed(err) || photo === undefined || photo.main === undefined) {
      console.error('[CameraSession] photoAvailable 无效', JSON.stringify(err));
      this.finishCapture(null);
      return;
    }

    const imageObj: image.Image = photo.main;
    this.extractJpegBuffer(imageObj, (jpegBuffer: ArrayBuffer | null, width: number, height: number) => {
      try {
        imageObj.release();
      } catch (releaseErr) {
        console.warn('[CameraSession] image.release 失败', JSON.stringify(releaseErr));
      }

      if (jpegBuffer === null || jpegBuffer.byteLength === 0) {
        console.error('[CameraSession] 未能提取 JPEG 数据');
        this.finishCapture(null);
        return;
      }

      console.info(`[CameraSession] 拍照成功 jpegBytes=${jpegBuffer.byteLength}`);
      this.finishCapture({
        data: jpegBuffer,
        width: width,
        height: height,
        format: 'jpeg'
      });
    });
  }

  /** 从 photo.main 读取 JPEG 字节（必须先拷贝再 release） */
  private extractJpegBuffer(
    imageObj: image.Image,
    done: (buffer: ArrayBuffer | null, width: number, height: number) => void
  ): void {
    imageObj.getComponent(image.ComponentType.JPEG, (compErr: BusinessError, component: image.Component) => {
      if (CameraSessionManager.isCallbackFailed(compErr)) {
        console.error('[CameraSession] getComponent(JPEG) 错误', JSON.stringify(compErr));
        done(null, 0, 0);
        return;
      }
      if (component === undefined || component.byteBuffer === undefined) {
        console.error('[CameraSession] JPEG byteBuffer 为空');
        done(null, 0, 0);
        return;
      }
      const srcBuffer: ArrayBuffer = component.byteBuffer;
      if (srcBuffer.byteLength === 0) {
        console.error('[CameraSession] JPEG 长度为 0');
        done(null, 0, 0);
        return;
      }
      done(CameraSessionManager.copyBuffer(srcBuffer), 0, 0);
    });
  }

  private finishCapture(result: CapturedImage | null): void {
    this.clearCaptureTimeout();
    const finish = this.captureFinish;
    this.captureFinish = null;
    if (finish !== null) {
      finish(result);
    }
  }

  private clearCaptureTimeout(): void {
    if (this.captureTimeoutId >= 0) {
      clearTimeout(this.captureTimeoutId);
      this.captureTimeoutId = -1;
    }
  }

  updateLightLevel(level: number): void {
    this.lightLevel = Math.max(0, Math.min(1, level / 255));
  }

  getLightLevel(): number {
    return this.lightLevel;
  }

  /** 设备是否支持数码变焦 */
  isZoomSupported(): boolean {
    const range = this.getZoomRatioRange();
    return range.max - range.min > 0.05;
  }

  getZoomRatioRange(): ZoomRatioRange {
    if (this.session === null) {
      return { min: 1, max: 1 };
    }
    try {
      const range = this.session.getZoomRatioRange();
      return { min: range[0], max: range[1] };
    } catch (err) {
      console.warn('[CameraSession] getZoomRatioRange 失败', JSON.stringify(err));
      return { min: 1, max: 1 };
    }
  }

  /** 设置变焦；不支持时静默忽略 */
  setZoomRatio(ratio: number): void {
    if (this.session === null) {
      return;
    }
    try {
      const range = this.getZoomRatioRange();
      const clamped = Math.max(range.min, Math.min(range.max, ratio));
      this.session.setZoomRatio(clamped);
      this.zoomRatio = clamped;
    } catch (err) {
      console.warn('[CameraSession] setZoomRatio 失败', JSON.stringify(err));
    }
  }

  getZoomRatio(): number {
    return this.zoomRatio;
  }

  /** 按 Surface 宽高比选择 previewProfile */
  private static pickPreviewProfile(profiles: Array<camera.Profile>, viewRatio: number): camera.Profile {
    let bestProfile = profiles[0];
    let minDiff = Number.MAX_VALUE;

    for (let i = 0; i < profiles.length; i++) {
      const profile = profiles[i];
      const landscapeRatio = profile.size.width / profile.size.height;
      const portraitRatio = profile.size.height / profile.size.width;
      const diffLandscape = Math.abs(landscapeRatio - viewRatio);
      const diffPortrait = Math.abs(portraitRatio - viewRatio);
      const diff = Math.min(diffLandscape, diffPortrait);
      if (diff < minDiff) {
        minDiff = diff;
        bestProfile = profile;
      }
    }

    console.info(
      `[CameraSession] 选中预览 ${bestProfile.size.width}x${bestProfile.size.height}, 目标比例=${viewRatio.toFixed(3)}`
    );
    return bestProfile;
  }

  /** 拍照 profile 尽量与 preview 同分辨率/同宽高比（官方要求一致） */
  private static pickPhotoProfile(
    profiles: Array<camera.Profile>,
    previewProfile: camera.Profile
  ): camera.Profile {
    for (let i = 0; i < profiles.length; i++) {
      const profile = profiles[i];
      if (profile.size.width === previewProfile.size.width &&
        profile.size.height === previewProfile.size.height) {
        return profile;
      }
    }

    const previewRatio = previewProfile.size.width / previewProfile.size.height;
    let bestProfile = profiles[0];
    let minDiff = Number.MAX_VALUE;
    for (let i = 0; i < profiles.length; i++) {
      const profile = profiles[i];
      if (profile.size.width > 1920 || profile.size.height > 1920) {
        continue;
      }
      const ratio = profile.size.width / profile.size.height;
      const diff = Math.abs(ratio - previewRatio);
      if (diff < minDiff) {
        minDiff = diff;
        bestProfile = profile;
      }
    }
    return bestProfile;
  }

  async release(): Promise<void> {
    this.finishCapture(null);
    this.isCapturing = false;
    this.previewFrameStart = null;
    this.frameStartNotified = false;
    this.isRunning = false;
    this.previewWidth = 0;
    this.previewHeight = 0;
    try {
      if (this.session !== null) {
        await this.session.stop();
        this.session.release();
        this.session = null;
      }
    } catch (err) {
      console.error('[CameraSession] 停止会话失败', JSON.stringify(err));
    }
    try {
      if (this.previewOutput !== null) {
        this.previewOutput.release();
        this.previewOutput = null;
      }
      if (this.photoOutput !== null) {
        this.photoOutput.release();
        this.photoOutput = null;
      }
      if (this.cameraInput !== null) {
        await this.cameraInput.close();
        this.cameraInput = null;
      }
    } catch (err) {
      console.error('[CameraSession] 释放输出失败', JSON.stringify(err));
    }
    this.cameraManager = null;
  }
}
