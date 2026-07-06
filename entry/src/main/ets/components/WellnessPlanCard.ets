/**
 * 四维养生方案卡片组件
 * 展示古籍原文摘录与出处，供用户自行查阅
 */
import { WellnessCitation, WellnessPlan } from '../common/types/AppTypes';

@Component
export struct WellnessPlanCard {
  @Prop plan: WellnessPlan = {
    diet: [], exercise: [], schedule: [], emotion: [],
    citationNotice: ''
  };

  @Builder
  CitationSection(title: string, icon: string, items: WellnessCitation[]) {
    Column() {
      Row() {
        Text(icon).fontSize(16).margin({ right: 8 })
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .margin({ bottom: 8 })

      if (items.length === 0) {
        Text('暂无对应古籍摘录')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
      } else {
        ForEach(items, (item: WellnessCitation, index: number) => {
          Column() {
            Text(`${index + 1}. ${item.source} · ${item.chapter}`)
              .fontSize(12)
              .fontColor($r('app.color.primary'))
              .fontWeight(FontWeight.Medium)
              .margin({ bottom: 4 })
            Text(`「${item.originalText}」`)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .lineHeight(22)
              .fontStyle(FontStyle.Italic)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ left: 4, bottom: 10 })
        }, (item: WellnessCitation) => item.entryId)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 16 })
  }

  build() {
    Column() {
      Text('以下摘录均来自知识库所引古籍，请自行查阅原典理解，本应用不作延伸解读。')
        .fontSize(11)
        .fontColor($r('app.color.warning'))
        .lineHeight(18)
        .margin({ bottom: 12 })

      this.CitationSection('饮食 · 古籍原文', '🍵', this.plan.diet)
      Divider().color($r('app.color.divider')).margin({ bottom: 12 })
      this.CitationSection('运动 · 古籍原文', '🏃', this.plan.exercise)
      Divider().color($r('app.color.divider')).margin({ bottom: 12 })
      this.CitationSection('作息 · 古籍原文', '🌙', this.plan.schedule)
      Divider().color($r('app.color.divider')).margin({ bottom: 12 })
      this.CitationSection('情绪 · 古籍原文', '🧘', this.plan.emotion)

      if (this.plan.citationNotice.length > 0) {
        Text(this.plan.citationNotice)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(18)
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.divider') })
  }
}
