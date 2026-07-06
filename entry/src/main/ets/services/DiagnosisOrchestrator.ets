/**
 * 面诊自测核心编排服务
 * 串联各模块完成完整自测流程，各模块通过 ModuleRegistry 解耦调用
 */
import { CapturedImage, DiagnosisReport, FaceAppearanceFeature, Region25SessionResult, TextGenerationRequest, UserProfile } from '../common/types/AppTypes';
import { AppState } from '../common/AppBootstrap';
import { ReportRenderModule } from '../modules/report/ReportRenderModule';
import { ModuleRegistry } from '../common/ModuleRegistry';
import { TextGenerationService } from './TextGenerationService';
import { ImageBrightnessUtil } from '../common/utils/ImageBrightnessUtil';

export class DiagnosisOrchestrator {
  private textGenService: TextGenerationService;
  private reportRender: ReportRenderModule;

  constructor(textGenService: TextGenerationService) {
    this.textGenService = textGenService;
    this.reportRender = new ReportRenderModule();
  }

  /**
   * 执行完整自测流程
   * @param measuredBrightness 拍照后本地实测亮度（0-255），用于光线判定与回写
   */
  async runDiagnosis(
    captured: CapturedImage,
    profile?: UserProfile,
    measuredBrightness?: number
  ): Promise<DiagnosisReport> {
    const modelConfig = ModuleRegistry.getModelConfig();
    const config = modelConfig.getConfig();
    const phoneAuth = ModuleRegistry.getPhoneAuth();

    if (!phoneAuth.isPhoneRegistered()) {
      throw new Error('请先注册手机号');
    }

    const vision = ModuleRegistry.getVision();
    const knowledge = ModuleRegistry.getKnowledge();
    const wellness = ModuleRegistry.getWellness();
    const compliance = ModuleRegistry.getCompliance();
    const camera = ModuleRegistry.getCamera();

    AppState.currentRegion25 = null;

    // 步骤1：云端 25 色部 / 视觉或本地规则兜底（传入用户资料供性别校验）
    const features: FaceAppearanceFeature = await vision.analyzeFace(captured, profile);

    // 以本地实测亮度为准，避免 AI 误报过暗
    if (measuredBrightness !== undefined && measuredBrightness > 0) {
      features.averageBrightness = measuredBrightness;
    } else {
      features.averageBrightness = ImageBrightnessUtil.normalize(features.averageBrightness);
    }
    // 本地亮度正常时，不因 AI 低置信度误判为光线问题
    if (measuredBrightness !== undefined && measuredBrightness >= 55 && features.confidence < 0.35) {
      features.confidence = 0.55;
    }

    camera.updateLightLevel(features.averageBrightness);
    // 步骤2：古籍知识库评分匹配
    const ancientEntries = knowledge.matchByFeatures(features);

    // 步骤3：联网文案生成
    const textRequest: TextGenerationRequest = {
      features: features,
      ancientEntries: ancientEntries,
      profile: profile
    };
    const textResult = await this.textGenService.generate(textRequest);

    // 步骤4：四维养生方案
    const wellnessPlan = wellness.generatePlan(ancientEntries, profile);

    // 步骤5：组装报告（有 25 色部时摘要用综合句，不再重复八区排版）
    const region25 = AppState.currentRegion25 ?? undefined;
    const rawSummary = this.reportRender.resolveAppearanceSummary(features, region25);
    // 25 色部综合文案已在服务端规避敏感词，避免「异常」等词被替换成 ** 导致显示残缺
    const appearanceSummary = region25 !== undefined
      ? rawSummary
      : compliance.filterSensitiveWords(rawSummary);

    const report = this.reportRender.assembleReport(
      features,
      appearanceSummary,
      textResult.culturalInterpretation,
      textResult.formattedReferences,
      wellnessPlan,
      region25
    );

    // 步骤6：立即销毁面部图像数据
    camera.destroyImageData();

    return report;
  }
}
