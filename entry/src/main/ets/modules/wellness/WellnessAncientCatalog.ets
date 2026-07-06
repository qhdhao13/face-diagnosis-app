/**
 * 四维养护方案 · 古籍条目索引
 * 按气色类型与维度映射知识库 entryId，输出原文供用户自行查阅
 */
import { AncientTextEntry, WellnessCitation } from '../../common/types/AppTypes';
import { ANCIENT_KNOWLEDGE_BASE } from '../knowledge/AncientKnowledgeData';

/** 养护维度 */
type WellnessDimension = 'diet' | 'exercise' | 'schedule' | 'emotion';

export class WellnessAncientCatalog {
  private static entryMap: Map<string, AncientTextEntry> = WellnessAncientCatalog.buildEntryMap();

  private static buildEntryMap(): Map<string, AncientTextEntry> {
    const map: Map<string, AncientTextEntry> = new Map();
    for (const entry of ANCIENT_KNOWLEDGE_BASE) {
      map.set(entry.id, entry);
    }
    return map;
  }

  /**
   * 为某一维度选取古籍原文（优先已匹配条目，再按目录补全）
   */
  static pickCitations(
    dimension: WellnessDimension,
    complexionKey: string,
    matched: AncientTextEntry[],
    maxCount: number = 3
  ): WellnessCitation[] {
    const result: WellnessCitation[] = [];
    const usedIds: Set<string> = new Set();

    for (const entry of matched) {
      if (result.length >= maxCount) {
        break;
      }
      if (WellnessAncientCatalog.matchesDimension(entry, dimension) && !usedIds.has(entry.id)) {
        result.push(WellnessAncientCatalog.toCitation(entry));
        usedIds.add(entry.id);
      }
    }

    const ids = WellnessAncientCatalog.getCatalogIds(dimension, complexionKey);
    for (let i = 0; i < ids.length; i++) {
      if (result.length >= maxCount) {
        break;
      }
      const id = ids[i];
      if (usedIds.has(id)) {
        continue;
      }
      const entry = WellnessAncientCatalog.entryMap.get(id);
      if (entry !== undefined) {
        result.push(WellnessAncientCatalog.toCitation(entry));
        usedIds.add(id);
      }
    }

    return result;
  }

  /** 按维度与气色返回条目 ID 列表（ArkTS 需显式分支，不可用嵌套对象字面量） */
  private static getCatalogIds(dimension: WellnessDimension, complexionKey: string): string[] {
    if (dimension === 'diet') {
      if (complexionKey === '偏白') {
        return ['ls008', 'wh005', 'general005', 'wz003'];
      }
      if (complexionKey === '偏黄') {
        return ['ls009', 'wh006', 'general005', 'ls001'];
      }
      if (complexionKey === '偏红') {
        return ['ls010', 'wh007', 'wz003', 'wz008'];
      }
      if (complexionKey === '偏暗沉') {
        return ['wh008', 'wz010', 'wh003', 'ls006'];
      }
      return ['general005', 'general001', 'wh001', 'ls007'];
    }

    if (dimension === 'exercise') {
      if (complexionKey === '偏白') {
        return ['general004', 'wh005', 'general002'];
      }
      if (complexionKey === '偏黄') {
        return ['general004', 'ls009', 'general002'];
      }
      if (complexionKey === '偏红') {
        return ['general004', 'ls003', 'wh007'];
      }
      if (complexionKey === '偏暗沉') {
        return ['general004', 'wh002', 'ls007'];
      }
      return ['general004', 'general002', 'wh001'];
    }

    if (dimension === 'schedule') {
      if (complexionKey === '偏白') {
        return ['ls002', 'general001', 'wz007', 'wh004'];
      }
      if (complexionKey === '偏黄') {
        return ['general001', 'ls009', 'general002'];
      }
      if (complexionKey === '偏红') {
        return ['ls003', 'ls010', 'wh007'];
      }
      if (complexionKey === '偏暗沉') {
        return ['wz004', 'ls006', 'wh004', 'wz009'];
      }
      return ['general001', 'general002', 'ls007', 'wh011'];
    }

    // emotion
    if (complexionKey === '偏白') {
      return ['general003', 'wz007', 'wh011'];
    }
    if (complexionKey === '偏黄') {
      return ['general003', 'wz001', 'wh001'];
    }
    if (complexionKey === '偏红') {
      return ['ls003', 'ls010', 'general003', 'wz005'];
    }
    if (complexionKey === '偏暗沉') {
      return ['general003', 'ls004', 'wh004', 'wh010'];
    }
    return ['general003', 'wh001', 'wz005'];
  }

  /** 维度关键词列表 */
  private static getDimensionKeywords(dimension: WellnessDimension): string[] {
    if (dimension === 'diet') {
      return ['食', '饮', '谷', '果', '畜', '菜', '味', '饱', '饥', '盐', '水', '润', '燥', '温', '冷', '生'];
    }
    if (dimension === 'exercise') {
      return ['劳', '行', '动', '卧', '立', '坐', '筋', '肉', '骨', '气'];
    }
    if (dimension === 'schedule') {
      return ['寝', '起', '睡', '夜', '早', '晚', '起居', '作', '时', '季', '藏'];
    }
    return ['情', '怒', '喜', '思', '忧', '恐', '躁', '静', '郁', '心'];
  }

  private static matchesDimension(entry: AncientTextEntry, dimension: WellnessDimension): boolean {
    const text = entry.originalText + entry.chapter;
    const keywords = WellnessAncientCatalog.getDimensionKeywords(dimension);
    for (let i = 0; i < keywords.length; i++) {
      if (text.indexOf(keywords[i]) >= 0) {
        return true;
      }
    }
    return false;
  }

  private static toCitation(entry: AncientTextEntry): WellnessCitation {
    const citation: WellnessCitation = {
      entryId: entry.id,
      source: entry.source,
      chapter: entry.chapter,
      originalText: entry.originalText
    };
    return citation;
  }
}
