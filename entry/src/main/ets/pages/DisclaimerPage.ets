/**
 * 免责声明详情页
 */
import { ComplianceTexts } from '../common/constants/AppConstants';
import { NavigationHelper } from '../common/utils/NavigationHelper';

@Entry
@Component
struct DisclaimerPage {
  private uiContext: UIContext = this.getUIContext();

  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(22)
          .fontColor($r('app.color.primary'))
          .onClick(() => NavigationHelper.back(this.uiContext))
        Text('免责声明')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(22)
      }
      .width('100%')
      .padding(16)

      Scroll() {
        Column() {
          Text(ComplianceTexts.STARTUP_DISCLAIMER)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .lineHeight(24)
            .margin({ bottom: 20 })

          Text(ComplianceTexts.COMMERCIAL_NOTICE)
            .fontSize(14)
            .fontColor($r('app.color.warning'))
            .lineHeight(24)
        }
        .padding({ left: 16, right: 16, bottom: 32 })
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
