/**
 * 首页
 * 展示产品介绍、启动免责弹窗、导航入口
 */
import { common } from '@kit.AbilityKit';
import { AppBootstrap, AppState } from '../common/AppBootstrap';
import { DisclaimerDialog } from '../components/DisclaimerDialog';
import { ComplianceTexts } from '../common/constants/AppConstants';
import { NavigationHelper } from '../common/utils/NavigationHelper';

@Entry
@Component
struct Index {
  @State showDisclaimer: boolean = false;
  private uiContext: UIContext = this.getUIContext();

  disclaimerController: CustomDialogController = new CustomDialogController({
    builder: DisclaimerDialog({
      onAccept: () => {
        this.acceptDisclaimer();
      },
      onReject: () => {
        // 用户拒绝则提示后停留
      }
    }),
    autoCancel: false,
    alignment: DialogAlignment.Center
  });

  async aboutToAppear(): Promise<void> {
    await AppBootstrap.initialize(this.uiContext.getHostContext() as common.UIAbilityContext);
    if (AppState.complianceModule !== null) {
      const needShow = await AppState.complianceModule.shouldShowStartupDisclaimer();
      if (needShow) {
        this.disclaimerController.open();
      }
    }
  }

  async acceptDisclaimer(): Promise<void> {
    if (AppState.complianceModule !== null) {
      await AppState.complianceModule.markDisclaimerAccepted();
    }
  }

  build() {
    Column() {
      // 顶部装饰
      Column() {
        Text('古籍面诊')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))
        Text('养生文化自测')
          .fontSize(18)
          .fontColor($r('app.color.primary_light'))
          .margin({ top: 4 })
      }
      .margin({ top: 80, bottom: 40 })

      // 产品介绍
      Column() {
        Text('传统中医古籍文化趣味自测工具')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 12 })
        Text('基于《灵枢·五色》《望诊遵经》《中医色诊学》')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 8 })
        Text('古人养生观察参考 · 非医疗软件')
          .fontSize(13)
          .fontColor($r('app.color.warning'))
      }
      .padding(20)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(16)
      .width('85%')
      .margin({ bottom: 40 })

      // 功能入口
      Button('开始面诊自测')
        .width('75%')
        .height(52)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.primary'))
        .borderRadius(26)
        .margin({ bottom: 16 })
        .onClick(() => {
          NavigationHelper.push(this.uiContext, 'pages/ScanPage');
        })

      Button('设置')
        .width('75%')
        .height(44)
        .fontSize(15)
        .fontColor($r('app.color.primary'))
        .backgroundColor(Color.Transparent)
        .border({ width: 1, color: $r('app.color.primary') })
        .borderRadius(22)
        .margin({ bottom: 12 })
        .onClick(() => {
          NavigationHelper.push(this.uiContext, 'pages/SettingsPage');
        })

      Text('隐私政策')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .decoration({ type: TextDecorationType.Underline })
        .onClick(() => {
          NavigationHelper.push(this.uiContext, 'pages/PrivacyPage');
        })

      Text('免责声明')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .decoration({ type: TextDecorationType.Underline })
        .margin({ top: 8 })
        .onClick(() => {
          NavigationHelper.push(this.uiContext, 'pages/DisclaimerPage');
        })

      Blank()

      // 底部固定免责
      Text(ComplianceTexts.REPORT_FOOTER)
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24, bottom: 24 })
        .lineHeight(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
