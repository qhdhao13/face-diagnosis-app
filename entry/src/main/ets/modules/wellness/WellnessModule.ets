/**
 * 模块5：四维养生方案生成模块
 * 方案内容均为古籍原文摘录 + 出处，供用户自行查阅原典
 */
import { AncientTextEntry, IWellnessModule, UserProfile, WellnessPlan } from '../../common/types/AppTypes';
import { ComplianceTexts } from '../../common/constants/AppConstants';
import { WellnessAncientCatalog } from './WellnessAncientCatalog';

export class WellnessModule implements IWellnessModule {
  /**
   * 根据古籍匹配结果生成四维养护引用方案
   * 不含 App 自撰科普，仅摘录原文
   */
  generatePlan(entries: AncientTextEntry[], profile?: UserProfile): WellnessPlan {
    const complexionKey = WellnessModule.detectComplexionKey(entries);

    const plan: WellnessPlan = {
      diet: WellnessAncientCatalog.pickCitations('diet', complexionKey, entries, 3),
      exercise: WellnessAncientCatalog.pickCitations('exercise', complexionKey, entries, 2),
      schedule: WellnessAncientCatalog.pickCitations('schedule', complexionKey, entries, 3),
      emotion: WellnessAncientCatalog.pickCitations('emotion', complexionKey, entries, 2),
      citationNotice: ComplianceTexts.WELLNESS_CITATION_NOTICE
    };

    // 年长者补充一条通用起居原文（仍来自古籍，非 App 自撰）
    if (profile !== undefined && profile.age > 60 && plan.schedule.length < 3) {
      const extra = WellnessAncientCatalog.pickCitations('schedule', '通用', entries, 1);
      for (let i = 0; i < extra.length; i++) {
        const item = extra[i];
        let alreadyHas = false;
        for (let j = 0; j < plan.schedule.length; j++) {
          if (plan.schedule[j].entryId === item.entryId) {
            alreadyHas = true;
            break;
          }
        }
        if (!alreadyHas) {
          plan.schedule.push(item);
          break;
        }
      }
    }

    return plan;
  }

  /** 从古籍条目中推断气色类型 */
  private static detectComplexionKey(entries: AncientTextEntry[]): string {
    const allTags: string[] = [];
    for (const entry of entries) {
      allTags.push(...entry.featureTags);
    }
    if (allTags.some((t: string) => t.includes('偏白'))) {
      return '偏白';
    }
    if (allTags.some((t: string) => t.includes('偏黄'))) {
      return '偏黄';
    }
    if (allTags.some((t: string) => t.includes('偏红') || t.includes('泛红'))) {
      return '偏红';
    }
    if (allTags.some((t: string) => t.includes('偏暗沉') || t.includes('暗沉'))) {
      return '偏暗沉';
    }
    return '通用';
  }
}
