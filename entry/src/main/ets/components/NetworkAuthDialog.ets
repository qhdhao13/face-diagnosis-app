/**
 * 联网授权弹窗组件
 */
import { NetworkAuthLevel } from '../common/types/AppTypes';

@CustomDialog
export struct NetworkAuthDialog {
  controller: CustomDialogController;
  onSelect: (level: NetworkAuthLevel) => void = () => {};

  build() {
    Column() {
      Text('联网授权')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 12 })

      Text('自测需联网并将面部照片上传至 AI 服务分析。请选择授权方式：')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(22)
        .margin({ bottom: 20 })

      Button('仅本次授权')
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor($r('app.color.primary'))
        .margin({ bottom: 8 })
        .onClick(() => {
          this.onSelect(NetworkAuthLevel.ONCE);
          this.controller.close();
        })

      Button('永久授权')
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor($r('app.color.primary_light'))
        .margin({ bottom: 8 })
        .onClick(() => {
          this.onSelect(NetworkAuthLevel.ALWAYS);
          this.controller.close();
        })

      Button('拒绝联网')
        .width('100%')
        .height(44)
        .fontSize(14)
        .backgroundColor($r('app.color.divider'))
        .fontColor($r('app.color.text_secondary'))
        .onClick(() => {
          this.onSelect(NetworkAuthLevel.DENY);
          this.controller.close();
        })
    }
    .padding(24)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(16)
    .width('85%')
  }
}
