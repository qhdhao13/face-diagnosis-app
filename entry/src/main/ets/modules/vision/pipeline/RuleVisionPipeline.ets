/**
 * 规则视觉管线（阶段 1 · 兜底引擎）
 * 鸿蒙人脸检测 + 动态分区 + RGB 规则气色映射
 */
import { common } from '@kit.AbilityKit';
import { CapturedImage, FaceAppearanceFeature } from '../../../common/types/AppTypes';
import { FaceDetectorBridge } from '../FaceDetectorBridge';
import { ImageColorAnalyzer } from '../ImageColorAnalyzer';
import { IVisionPipeline } from './IVisionPipeline';

export class RuleVisionPipeline implements IVisionPipeline {
  private faceDetector: FaceDetectorBridge = new FaceDetectorBridge();
  private colorAnalyzer: ImageColorAnalyzer = new ImageColorAnalyzer();
  private initialized: boolean = false;
  private faceDetectEnabled: boolean = false;

  async init(_context: common.UIAbilityContext): Promise<void> {
    this.faceDetectEnabled = await this.faceDetector.init();
    this.initialized = true;
  }

  isReady(): boolean {
    return this.initialized;
  }

  getEngineLabel(): string {
    return this.faceDetectEnabled ? '规则引擎（人脸检测+RGB）' : '规则引擎（RGB 居中分区）';
  }

  async analyze(captured: CapturedImage): Promise<FaceAppearanceFeature | null> {
    if (!this.initialized) {
      return null;
    }

    const faceBox = this.faceDetectEnabled ? await this.faceDetector.detectFace(captured) : null;
    const result = await this.colorAnalyzer.analyze(captured, faceBox ?? undefined);
    result.analysisEngine = faceBox !== null ? 'rule_with_face_detect' : 'rule';
    return result;
  }
}
