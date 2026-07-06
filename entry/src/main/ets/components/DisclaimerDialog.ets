/**
 * 启动免责弹窗组件
 */
import { ComplianceTexts } from '../common/constants/AppConstants';

@CustomDialog
export struct DisclaimerDialog {
  controller: CustomDialogController;
  onAccept: () => void = () => {};
  onReject: () => void = () => {};

  build() {
    Column() {
      Text('重要声明')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 16 })

      Scroll() {
        Text(ComplianceTexts.STARTUP_DISCLAIMER)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
      }
      .height(200)
      .margin({ bottom: 20 })

      Row() {
        Button('不同意并退出')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.divider'))
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.onReject();
            this.controller.close();
          })

        Blank().width(12)

        Button('我已知晓并同意')
          .fontSize(14)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.primary'))
          .layoutWeight(1)
          .height(44)
          .onClick(() => {
            this.onAccept();
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding(24)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(16)
    .width('85%')
  }
}
