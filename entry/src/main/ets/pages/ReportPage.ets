/**
 * 模块6：报告UI渲染页
 * 展示面部状态、古籍引用、养生方案、免责声明
 */
import { AppState } from '../common/AppBootstrap';
import { AncientTextEntry, DiagnosisReport } from '../common/types/AppTypes';
import { AncientReferenceCard } from '../components/AncientReferenceCard';
import { WellnessPlanCard } from '../components/WellnessPlanCard';
import { ComplianceTexts } from '../common/constants/AppConstants';
import { NavigationHelper } from '../common/utils/NavigationHelper';
import { ReportExportUtil } from '../common/utils/ReportExportUtil';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct ReportPage {
  @State report: DiagnosisReport | null = null;
  @State exportHint: string = '';
  @State exporting: boolean = false;
  private uiContext: UIContext = this.getUIContext();

  aboutToAppear(): void {
    this.report = AppState.currentReport;
  }

  /** 导出报告：保存 txt 并调起系统分享/保存面板 */
  async downloadReport(): Promise<void> {
    if (this.report === null || this.exporting) {
      return;
    }
    this.exporting = true;
    this.exportHint = '正在生成报告…';
    try {
      const hostContext = this.uiContext.getHostContext() as common.UIAbilityContext;
      const path = await ReportExportUtil.saveAndShare(hostContext, this.report);
      this.exportHint = `报告已生成，可在分享面板保存\n${path}`;
    } catch (err) {
      this.exportHint = '导出失败，请重试';
      console.error('[ReportPage] export failed', JSON.stringify(err));
    } finally {
      this.exporting = false;
    }
  }

  build() {
    Column() {
      // 顶部导航
      Row() {
        Text('← 返回')
          .fontSize(16)
          .fontColor($r('app.color.primary'))
          .onClick(() => NavigationHelper.back(this.uiContext))
        Text('养生参考报告')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Text(this.exporting ? '…' : '下载')
          .fontSize(16)
          .fontColor(this.report !== null ? $r('app.color.primary') : $r('app.color.text_secondary'))
          .width(60)
          .textAlign(TextAlign.End)
          .onClick(() => this.downloadReport())
      }
      .width('100%')
      .padding(16)

      if (this.exportHint.length > 0) {
        Text(this.exportHint)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
      }

      if (this.report === null) {
        Column() {
          Text('暂无报告数据')
            .fontSize(16)
            .fontColor($r('app.color.text_secondary'))
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            // 25 色部模式：合并为一块；否则保留八区摘要
            if (this.report!.region25 !== undefined) {
              Column() {
                Text('二十五明堂色部色诊')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.primary'))
                  .margin({ bottom: 8 })
                Text(`会话 ID：${this.report!.region25!.sessionId}`)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ bottom: 8 })
                Image(this.report!.region25!.annotatedImageUrl)
                  .width('100%')
                  .height(280)
                  .objectFit(ImageFit.Contain)
                  .borderRadius(8)
                  .margin({ bottom: 12 })
                Text('综合')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.primary'))
                  .margin({ bottom: 6 })
                Text(this.report!.appearanceSummary)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .lineHeight(22)
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .margin({ bottom: 12 })
                Text('分项（25 区）')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.primary'))
                  .margin({ bottom: 6 })
                ForEach(this.report!.region25!.lineItems, (line: string, index: number) => {
                  Text(`${index + 1}. ${line}`)
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .lineHeight(20)
                    .width('100%')
                    .margin({ bottom: 4 })
                }, (line: string, index: number) => `${index}_${line}`)
                Text(this.report!.region25!.disclaimer)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 8 })
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(12)
              .margin({ bottom: 16 })
            } else {
              Column() {
                Text('面部外观观察参考')
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.primary'))
                  .margin({ bottom: 12 })
                Text(this.report!.appearanceSummary)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .lineHeight(24)
                  .width('100%')
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.card_bg'))
              .borderRadius(12)
              .margin({ bottom: 16 })
            }

            // 古人养生文化解读
            Column() {
              Text('古人养生文化解读')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.primary'))
                .margin({ bottom: 12 })
              Text(this.report!.culturalInterpretation)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .lineHeight(22)
            }
            .width('100%')
            .padding(16)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(12)
            .margin({ bottom: 16 })

            // 4. 古籍溯源板块
            Text('古籍溯源')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary'))
              .width('100%')
              .margin({ bottom: 12 })

            ForEach(this.report!.ancientReferences, (entry: AncientTextEntry) => {
              AncientReferenceCard({ entry: entry })
            }, (entry: AncientTextEntry) => entry.id)

            // 5. 四维养护参考方案
            Text('四维养护参考方案（古籍原文摘录）')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.primary'))
              .width('100%')
              .margin({ bottom: 12, top: 8 })

            WellnessPlanCard({ plan: this.report!.wellnessPlan })

            // 6. 底部固定免责声明
            Column() {
              if (this.report!.features.analysisEngine !== undefined) {
                Text(`分析引擎：${this.report!.features.analysisEngine}`)
                  .fontSize(10)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ bottom: 8 })
              }
              Text(ComplianceTexts.REPORT_FOOTER)
                .fontSize(12)
                .fontColor($r('app.color.warning'))
                .lineHeight(18)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding(16)
            .backgroundColor('#FFF5F5')
            .borderRadius(8)
            .margin({ top: 8, bottom: 32 })
          }
          .padding({ left: 16, right: 16 })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
