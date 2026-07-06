/**
 * .om 三模型视觉管线（阶段 3 · 主路径）
 * MTCNN → MobileNetV3 → MobileCLIP；各阶段失败时使用对应降级能力
 */
import { common } from '@kit.AbilityKit';
import { CapturedImage, FaceAppearanceFeature, FaceBoundingBox, FaceRegionRect } from '../../../common/types/AppTypes';
import { FaceDetectorBridge } from '../FaceDetectorBridge';
import { FaceRegionLayout } from '../FaceRegionLayout';
import { ImageColorAnalyzer } from '../ImageColorAnalyzer';
import { ComplexionTagMapper } from '../ComplexionTagMapper';
import { OmModelKey, OmModelLoader } from '../OmModelLoader';
import { OmOutputParser } from '../OmOutputParser';
import { IVisionPipeline } from './IVisionPipeline';

export class OmVisionPipeline implements IVisionPipeline {
  private loader: OmModelLoader = new OmModelLoader();
  private faceDetector: FaceDetectorBridge = new FaceDetectorBridge();
  private colorAnalyzer: ImageColorAnalyzer = new ImageColorAnalyzer();
  private initialized: boolean = false;
  private faceDetectEnabled: boolean = false;

  async init(context: common.UIAbilityContext): Promise<void> {
    await this.loader.loadAll(context);
    ComplexionTagMapper.setEmbeddingTable(this.loader.getEmbeddingTable());
    this.faceDetectEnabled = await this.faceDetector.init();
    this.initialized = true;
  }

  isReady(): boolean {
    return this.initialized && this.loader.hasAnyModel();
  }

  getEngineLabel(): string {
    if (!this.loader.hasAnyModel()) {
      return '.om 三模型管线（模型文件未齐）';
    }
    if (this.loader.isMindSporeReady()) {
      return '.om 三模型管线（MindSpore 全量推理）';
    }
    if (this.loader.isRunnerReady(OmModelKey.MTCNN)) {
      return '.om 管线（Stage1 人脸检测已启用）';
    }
    return '.om 三模型管线（混合：检测+分区+规则气色）';
  }

  async analyze(captured: CapturedImage): Promise<FaceAppearanceFeature | null> {
    if (!this.isReady()) {
      return null;
    }

    const faceBox = await this.runStage1FaceDetect(captured);
    if (faceBox === null) {
      return null;
    }

    const regions = await this.runStage2Segmentation(captured, faceBox);
    const result = await this.runStage3Complexion(captured, regions, faceBox);
    if (result === null) {
      return null;
    }

    result.analysisEngine = this.loader.isMindSporeReady()
      ? 'om_pipeline'
      : (this.loader.isRunnerReady(OmModelKey.MTCNN) ? 'om_pipeline_partial' : 'om_pipeline_hybrid');
    return result;
  }

  private async runStage1FaceDetect(captured: CapturedImage): Promise<FaceBoundingBox | null> {
    if (this.loader.isRunnerReady(OmModelKey.MTCNN)) {
      const outputs = await this.loader.predictImageAll(OmModelKey.MTCNN, captured);
      const config = this.loader.getModelConfig(OmModelKey.MTCNN);
      if (outputs !== null && config !== null) {
        const omBox = OmOutputParser.parseFaceDetectOutputs(
          outputs,
          config.inputWidth,
          config.inputHeight,
          config.detectorType
        );
        if (omBox !== null) {
          return omBox;
        }
      }
    }
    if (this.faceDetectEnabled) {
      const sysBox = await this.faceDetector.detectFace(captured);
      if (sysBox !== null) {
        return sysBox;
      }
    }
    return {
      x: 0.15,
      y: 0.10,
      width: 0.70,
      height: 0.80,
      confidence: 0.4
    };
  }

  private async runStage2Segmentation(
    captured: CapturedImage,
    faceBox: FaceBoundingBox
  ): Promise<FaceRegionRect[]> {
    if (this.loader.hasModel(OmModelKey.MOBILENETV3) && this.loader.isRunnerReady(OmModelKey.MOBILENETV3)) {
      const output = await this.loader.predictImage(OmModelKey.MOBILENETV3, captured);
      const config = this.loader.getModelConfig(OmModelKey.MOBILENETV3);
      if (output !== null && config !== null) {
        const omRegions = OmOutputParser.parseSegmentationMask(
          output,
          faceBox,
          config.inputWidth,
          config.inputHeight
        );
        if (omRegions !== null && omRegions.length > 0) {
          return omRegions;
        }
      }
    }
    return FaceRegionLayout.buildRegions(faceBox);
  }

  private async runStage3Complexion(
    captured: CapturedImage,
    regions: FaceRegionRect[],
    faceBox: FaceBoundingBox
  ): Promise<FaceAppearanceFeature | null> {
    if (this.loader.hasModel(OmModelKey.MOBILECLIP) && this.loader.isRunnerReady(OmModelKey.MOBILECLIP)) {
      const output = await this.loader.predictImage(OmModelKey.MOBILECLIP, captured);
      if (output !== null) {
        const embedding = OmOutputParser.extractClipEmbedding(output);
        const clipTag = ComplexionTagMapper.mapFromEmbedding(embedding);
        const base = await this.colorAnalyzer.analyzeWithRegions(
          captured,
          regions,
          FaceRegionLayout.buildGlobalRegion(faceBox)
        );
        base.overallComplexion = clipTag;
        if (!base.matchTags.includes(clipTag)) {
          base.matchTags.unshift(clipTag);
        }
        return base;
      }
    }
    return await this.colorAnalyzer.analyzeWithRegions(
      captured,
      regions,
      FaceRegionLayout.buildGlobalRegion(faceBox)
    );
  }
}
