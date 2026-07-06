/**
 * 古籍引用卡片组件
 * 标准化展示：古籍原文 + 出处 + 白话释义
 */
import { AncientTextEntry } from '../common/types/AppTypes';

@Component
export struct AncientReferenceCard {
  @Prop entry: AncientTextEntry = {
    id: '', source: '', chapter: '', originalText: '', modernExplanation: '', featureTags: []
  };

  build() {
    Column() {
      Row() {
        Text('📜')
          .fontSize(16)
          .margin({ right: 8 })
        Text(`${this.entry.source} · ${this.entry.chapter}`)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))
      }
      .width('100%')
      .margin({ bottom: 10 })

      Column() {
        Text('【古籍原文】')
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .margin({ bottom: 4 })
        Text(this.entry.originalText)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .lineHeight(22)
      }
      .width('100%')
      .padding(12)
      .backgroundColor('#FFF8F0')
      .borderRadius(8)
      .margin({ bottom: 10 })

      Column() {
        Text('【白话释义】')
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .margin({ bottom: 4 })
        Text(this.entry.modernExplanation)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
    .margin({ bottom: 12 })
  }
}
