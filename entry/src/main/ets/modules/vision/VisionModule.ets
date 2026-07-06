/**
 * 模块3：视觉识别模块（云端主路径 + 本地规则兜底）
 * 主路径：CloudVisionService（多模态 API 看脸）
 * 兜底路径：RGB 规则引擎（断网 / 无 Key / API 失败）
 */
import { common } from '@kit.AbilityKit';
import { CapturedImage, FaceAppearanceFeature, IVisionModule, UserProfile, VisionEngineType } from '../../common/types/AppTypes';
import { CloudVisionService } from '../../services/CloudVisionService';
import { RuleVisionPipeline } from './pipeline/RuleVisionPipeline';

export class VisionModule implements IVisionModule {
  private cloudVision: CloudVisionService;
  private rulePipeline: RuleVisionPipeline = new RuleVisionPipeline();
  private engineMode: VisionEngineType = VisionEngineType.AUTO;
  private initialized: boolean = false;
  private lastEngineLabel: string = '未初始化';

  constructor(cloudVision: CloudVisionService) {
    this.cloudVision = cloudVision;
  }

  isModelReady(): boolean {
    return this.initialized;
  }

  getActiveEngineLabel(): string {
    return this.lastEngineLabel;
  }

  /** 启动时初始化本地规则兜底（无需加载端侧 .om） */
  async initModels(context: common.UIAbilityContext): Promise<void> {
    await this.rulePipeline.init(context);
    this.initialized = true;

    if (this.cloudVision.canUseCloudVision()) {
      this.lastEngineLabel = '云端 25 色部 Lab 分析（体验服）';
      console.info('[VisionModule] 云端 25 色部分析就绪');
    } else {
      this.lastEngineLabel = '本地规则引擎（未注册/无配额/无 Key 或离线）';
      console.info('[VisionModule] 云端未就绪，将使用本地规则兜底');
    }
  }

  /**
   * 分析面部外观
   * AUTO：优先云端 → 失败降级本地规则
   */
  async analyzeFace(image: CapturedImage, profile?: UserProfile): Promise<FaceAppearanceFeature> {
    if (!this.initialized || image.data.byteLength === 0) {
      return VisionModule.buildDefaultFeature();
    }

    try {
      if (this.engineMode === VisionEngineType.RULE) {
        return await this.runRuleOnly(image);
      }

      if (this.engineMode === VisionEngineType.CLOUD || this.engineMode === VisionEngineType.AUTO) {
        if (this.cloudVision.canUseCloudVision()) {
          try {
            const cloudResult = await this.cloudVision.analyzeFace(image, profile);
            this.lastEngineLabel = '云端 AI 视觉';
            return cloudResult;
          } catch (err) {
            const errMsg = err instanceof Error ? err.message : JSON.stringify(err);
            console.error('[VisionModule] 云端分析失败，降级规则引擎:', errMsg);
            if (this.engineMode === VisionEngineType.CLOUD) {
              return VisionModule.buildDefaultFeature();
            }
            const fallback = await this.runRuleOnly(image);
            fallback.analysisEngine = 'cloud_fallback_rule';
            return fallback;
          }
        }
      }

      if (this.engineMode === VisionEngineType.CLOUD) {
        return VisionModule.buildDefaultFeature();
      }

      return await this.runRuleOnly(image);
    } catch (err) {
      console.error('[VisionModule] 分析失败', JSON.stringify(err));
      return VisionModule.buildDefaultFeature();
    }
  }

  private async runRuleOnly(image: CapturedImage): Promise<FaceAppearanceFeature> {
    const ruleResult = await this.rulePipeline.analyze(image);
    this.lastEngineLabel = this.rulePipeline.getEngineLabel();
    if (ruleResult !== null) {
      if (ruleResult.analysisEngine === undefined) {
        ruleResult.analysisEngine = 'rule';
      }
      return ruleResult;
    }
    return VisionModule.buildDefaultFeature();
  }

  private static buildDefaultFeature(): FaceAppearanceFeature {
    return {
      overallComplexion: '气色尚可',
      forehead: '天庭额部明润尚匀，色泽均匀',
      leftCheek: '左颧颊气色尚可，色泽匀净',
      rightCheek: '右颧颊气色尚可，色泽匀净',
      nose: '鼻柱准头色泽自然',
      chin: '地阁颏部轮廓尚清',
      eyeArea: '目眶尚清，神彩平常',
      lipArea: '口唇唇色自然',
      details: ['整体气色观察参考'],
      confidence: 0.5,
      averageBrightness: 128,
      matchTags: ['通用', '整体气色尚可'],
      analysisEngine: 'fallback'
    };
  }
}
