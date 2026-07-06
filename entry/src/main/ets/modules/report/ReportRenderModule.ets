/**
 * 模块6：报告UI渲染模块
 * 负责报告数据格式化，与页面UI解耦
 */
import { DiagnosisReport, FaceAppearanceFeature, AncientTextEntry, WellnessPlan, Region25SessionResult } from '../../common/types/AppTypes';
import { ComplianceTexts } from '../../common/constants/AppConstants';
import { AppearanceSummaryFormatter } from './AppearanceSummaryFormatter';
import { Region25ClassicalSummary } from './Region25ClassicalSummary';

export class ReportRenderModule {
  /** 本地规则 / 自带 Key 云端：八区古籍格式摘要 */
  formatAppearanceSummary(features: FaceAppearanceFeature): string {
    return AppearanceSummaryFormatter.format(features);
  }

  /** 体验模式 25 色部：古籍体例综合（整体结论 + 三庭 + 传变 + 典籍提示） */
  formatRegion25Summary(session: Region25SessionResult): string {
    return Region25ClassicalSummary.build(session);
  }

  /** 根据是否有 25 色部选择展示用摘要 */
  resolveAppearanceSummary(features: FaceAppearanceFeature, region25?: Region25SessionResult): string {
    if (region25 !== undefined) {
      return this.formatRegion25Summary(region25);
    }
    return this.formatAppearanceSummary(features);
  }

  /** 组装完整报告对象 */
  assembleReport(
    features: FaceAppearanceFeature,
    appearanceSummary: string,
    culturalInterpretation: string,
    ancientReferences: AncientTextEntry[],
    wellnessPlan: WellnessPlan,
    region25?: Region25SessionResult
  ): DiagnosisReport {
    return {
      reportId: `RPT_${Date.now()}`,
      timestamp: Date.now(),
      appearanceSummary: appearanceSummary,
      features: features,
      ancientReferences: ancientReferences,
      culturalInterpretation: culturalInterpretation,
      wellnessPlan: wellnessPlan,
      disclaimer: ComplianceTexts.REPORT_FOOTER,
      region25: region25
    };
  }
}
