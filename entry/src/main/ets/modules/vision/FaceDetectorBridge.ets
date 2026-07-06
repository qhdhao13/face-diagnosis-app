/**
 * 人脸检测桥接层（阶段 1/2）
 * 当前 SDK 未暴露稳定 FaceDetector API，暂以默认居中分区兜底
 * 接入 MTCNN .om 或系统人脸检测 API 后，在此扩展 detectFace 实现
 */
import { CapturedImage, FaceBoundingBox } from '../../common/types/AppTypes';

export class FaceDetectorBridge {
  private ready: boolean = false;

  /** 初始化（预留系统人脸检测接入点） */
  async init(): Promise<boolean> {
    // 阶段1：CoreVisionKit 在当前 SDK 版本无 createFaceDetector，暂不启用
    this.ready = false;
    return false;
  }

  isReady(): boolean {
    return this.ready;
  }

  /**
   * 检测单张人脸；当前返回 null，上层使用 FaceRegionLayout 默认居中框
   */
  async detectFace(_captured: CapturedImage): Promise<FaceBoundingBox | null> {
    return null;
  }

  release(): void {
    this.ready = false;
  }
}
