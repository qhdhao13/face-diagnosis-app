/**
 * 报告导出：生成纯文本并保存到本地，调起系统分享面板（可存文件/转发）
 */
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { systemShare } from '@kit.ShareKit';
import { DiagnosisReport, WellnessPlan, WellnessCitation } from '../types/AppTypes';
import { ComplianceTexts } from '../constants/AppConstants';

export class ReportExportUtil {
  /** 将完整报告拼成可下载的纯文本 */
  static buildFullText(report: DiagnosisReport): string {
    const lines: string[] = [];
    const ts = new Date(report.timestamp);
    lines.push('古籍面诊自测 · 养生参考报告');
    lines.push(`报告编号：${report.reportId}`);
    lines.push(`生成时间：${ts.toLocaleString('zh-CN')}`);
    if (report.features.analysisEngine !== undefined) {
      lines.push(`分析引擎：${report.features.analysisEngine}`);
    }
    lines.push('');
    if (report.region25 !== undefined) {
      const r25 = report.region25;
      lines.push('='.repeat(40));
      lines.push('【二十五明堂色部色诊】');
      lines.push(`会话 ID：${r25.sessionId}`);
      lines.push(`标注图：${r25.annotatedImageUrl}`);
      lines.push('');
      lines.push('综合：');
      lines.push(report.appearanceSummary);
      lines.push('');
      lines.push('分项（25 区）：');
      for (let i = 0; i < r25.lineItems.length; i++) {
        lines.push(`${i + 1}. ${r25.lineItems[i]}`);
      }
      if (r25.disclaimer.length > 0) {
        lines.push('');
        lines.push(r25.disclaimer);
      }
    } else {
      lines.push('='.repeat(40));
      lines.push('【面部外观观察参考】');
      lines.push(report.appearanceSummary);
    }

    lines.push('');
    lines.push('='.repeat(40));
    lines.push('【古人养生文化解读】');
    lines.push(report.culturalInterpretation);

    lines.push('');
    lines.push('='.repeat(40));
    lines.push('【古籍溯源】');
    for (const entry of report.ancientReferences) {
      lines.push(`— ${entry.source} · ${entry.chapter}`);
      lines.push(entry.originalText);
      lines.push(`今释：${entry.modernExplanation}`);
      lines.push('');
    }

    lines.push('='.repeat(40));
    lines.push('【四维养护参考方案】');
    lines.push(ReportExportUtil.formatWellness(report.wellnessPlan));

    lines.push('');
    lines.push('='.repeat(40));
    lines.push(ComplianceTexts.REPORT_FOOTER);
    lines.push(report.disclaimer);
    return lines.join('\n');
  }

  private static formatWellness(plan: WellnessPlan): string {
    const parts: string[] = [];
    parts.push(`说明：${plan.citationNotice}`);
    parts.push('');
    parts.push('· 饮食');
    ReportExportUtil.appendCitations(parts, plan.diet);
    parts.push('· 运动');
    ReportExportUtil.appendCitations(parts, plan.exercise);
    parts.push('· 作息');
    ReportExportUtil.appendCitations(parts, plan.schedule);
    parts.push('· 情志');
    ReportExportUtil.appendCitations(parts, plan.emotion);
    return parts.join('\n');
  }

  private static appendCitations(parts: string[], items: WellnessCitation[]): void {
    if (items.length === 0) {
      parts.push('  （暂无匹配摘录）');
      return;
    }
    for (const c of items) {
      parts.push(`  ${c.source}：${c.originalText.substring(0, Math.min(80, c.originalText.length))}…`);
    }
  }

  /**
   * 写入应用目录并调起系统分享（用户可选「保存到文件」等）
   */
  static async saveAndShare(context: common.UIAbilityContext, report: DiagnosisReport): Promise<string> {
    const content = ReportExportUtil.buildFullText(report);
    const safeId = report.reportId.replace(/[^\w-]/g, '_');
    const fileName = `face_report_${safeId}.txt`;
    const dir = `${context.filesDir}/reports`;

    try {
      fileIo.mkdirSync(dir);
    } catch (_err) {
      // 目录已存在
    }

    const path = `${dir}/${fileName}`;
    // CREATE + TRUNC + WRITE_ONLY：创建/覆盖并只写
    const file = fileIo.openSync(path,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY);
    fileIo.writeSync(file.fd, content);
    fileIo.closeSync(file);

    const uri = fileUri.getUriFromPath(path);
    const shareData: systemShare.SharedData = new systemShare.SharedData({
      utd: uniformTypeDescriptor.UniformDataType.FILE,
      uri: uri,
      title: '面诊自测报告',
      description: '古籍面诊养生参考报告（文化自测，非医疗诊断）'
    });
    const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
    await controller.show(context, {});

    return path;
  }
}
