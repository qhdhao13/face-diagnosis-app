/**
 * 鸿蒙元服务卡片（2x2 / 2x4）
 * 轻量化入口，点击跳转主应用扫描页
 */
let cardLocalStorage: LocalStorage = new LocalStorage();

@Entry(cardLocalStorage)
@Component
struct WellnessWidgetCard {
  @LocalStorageProp('title') title: string = '古籍面诊养生';
  @LocalStorageProp('subtitle') subtitle: string = '传统文化自测工具';
  @LocalStorageProp('tip') tip: string = '点击开始自测';

  /** 点击卡片跳转主应用扫描页（postCardAction 为卡片全局 API，无需 import） */
  private openScanPage(): void {
    postCardAction(this, {
      action: 'router',
      bundleName: 'com.face.diagnosis.app',
      abilityName: 'EntryAbility',
      params: {
        url: 'pages/ScanPage'
      }
    });
  }

  build() {
    Column() {
      Text('🌿')
        .fontSize(28)
        .margin({ bottom: 4 })

      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor('#8B4513')
        .margin({ bottom: 2 })

      Text(this.subtitle)
        .fontSize(10)
        .fontColor('#6B5344')
        .margin({ bottom: 8 })

      Text(this.tip)
        .fontSize(10)
        .fontColor('#B8860B')
        .backgroundColor('#FFF8E7')
        .padding({ left: 8, right: 8, top: 4, bottom: 4 })
        .borderRadius(10)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F5F0E8')
    .borderRadius(16)
    .onClick(() => {
      this.openScanPage();
    })
  }
}
