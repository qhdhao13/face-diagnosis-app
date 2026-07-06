/**
 * 古籍知识库评分匹配引擎
 * 基于标签同义词 + 权重打分，替代简单字符串包含匹配
 */
import { AncientTextEntry, FaceAppearanceFeature } from '../../common/types/AppTypes';

/** 单条匹配结果（含得分） */
export interface ScoredEntry {
  entry: AncientTextEntry;
  score: number;
}

export class KnowledgeMatchEngine {
  /** 标签同义词表：统一不同表述到标准标签 */
  private static readonly SYNONYM_GROUPS: string[][] = [
    ['偏白', '色白', '偏白润', '明润偏白', '色泽偏白'],
    ['偏黄', '色黄', '略黄', '微黄'],
    ['偏红', '色红', '红润', '红活'],
    ['泛红', '略有泛红', '局部泛红', '颊红'],
    ['偏暗沉', '暗沉', '色暗', '明度偏低'],
    ['偏青白', '青白', '白而青'],
    ['浮肿', '面浮', '轮廓浮肿'],
    ['细纹', '略有细纹', '局部略有细纹', '纹理细纹'],
    ['纹理细腻', '肌理细腻', '细腻'],
    ['气色尚可', '整体气色尚可', '色泽均匀', '色泽自然', '整体气色观察参考'],
    ['略有暗沉', '眼周略有暗沉', '局部暗沉'],
    ['唇色偏淡', '唇淡', '唇色淡'],
    ['唇色略深', '唇深', '唇色深'],
    ['唇色红润', '唇红', '唇色自然'],
    ['额头', '天庭', '上庭', '额部'],
    ['左脸颊', '左颊', '蕃左', '左颧颊'],
    ['右脸颊', '右颊', '蕃右', '右颧颊'],
    ['鼻部', '明堂', '鼻区', '鼻柱', '准头'],
    ['下巴', '颏', '地阁', '下庭', '颏部'],
    ['眼周', '目下', '阙', '眉间', '目眶', '双眸'],
    ['唇部', '唇区', '唇珠', '口唇'],
    ['通用', '整体', '总则']
  ];

  /** 高权重标签：匹配到则加分更多 */
  private static readonly HIGH_WEIGHT_TAGS: Set<string> = new Set([
    '偏白', '偏黄', '偏红', '偏暗沉', '偏青白', '泛红', '通用'
  ]);

  /**
   * 对知识库条目打分排序，返回 Top N
   */
  match(features: FaceAppearanceFeature, knowledgeBase: AncientTextEntry[], topN: number = 5): AncientTextEntry[] {
    const featureTags: Set<string> = this.buildNormalizedTagSet(features);
    const scored: ScoredEntry[] = [];

    for (const entry of knowledgeBase) {
      const score = this.scoreEntry(entry, featureTags);
      if (score > 0) {
        scored.push({ entry: entry, score: score });
      }
    }

    scored.sort((a: ScoredEntry, b: ScoredEntry) => b.score - a.score);

    let results: AncientTextEntry[] = scored.slice(0, topN).map((s: ScoredEntry) => s.entry);

    // 不足 3 条时用「通用」条目补齐
    if (results.length < 3) {
      const generalPool = knowledgeBase.filter((e: AncientTextEntry) =>
        e.featureTags.includes('通用')
      );
      for (const ge of generalPool) {
        if (results.length >= topN) {
          break;
        }
        if (!results.some((r: AncientTextEntry) => r.id === ge.id)) {
          results.push(ge);
        }
      }
    }

    return results.slice(0, topN);
  }

  /** 从特征对象提取并归一化全部匹配标签 */
  buildNormalizedTagSet(features: FaceAppearanceFeature): Set<string> {
    const rawTags: string[] = [
      features.overallComplexion,
      features.forehead,
      features.leftCheek,
      features.rightCheek,
      features.nose,
      features.chin,
      features.eyeArea,
      features.lipArea,
      ...features.details,
      ...features.matchTags
    ];
    const normalized: Set<string> = new Set();
    for (const raw of rawTags) {
      const tags = this.normalizeTag(raw);
      tags.forEach((t: string) => normalized.add(t));
    }
    return normalized;
  }

  /** 对单条古籍计算匹配得分 */
  private scoreEntry(entry: AncientTextEntry, featureTags: Set<string>): number {
    let score = 0;
    for (const entryTag of entry.featureTags) {
      const entryNormalized = this.normalizeTag(entryTag);
      for (const en of entryNormalized) {
        if (featureTags.has(en)) {
          score += KnowledgeMatchEngine.HIGH_WEIGHT_TAGS.has(en) ? 3 : 2;
        } else {
          // 部分匹配：featureTag 与 entryTag 存在包含关系
          const tagArray: string[] = Array.from(featureTags);
          for (let i = 0; i < tagArray.length; i++) {
            const ft = tagArray[i];
            if (ft.includes(en) || en.includes(ft)) {
              score += 1;
              break;
            }
          }
        }
      }
    }
    return score;
  }

  /** 将原始描述归一化为标准标签集合 */
  private normalizeTag(raw: string): string[] {
    const result: Set<string> = new Set();
    result.add(raw);

    for (const group of KnowledgeMatchEngine.SYNONYM_GROUPS) {
      for (const synonym of group) {
        if (raw.includes(synonym) || synonym.includes(raw)) {
          group.forEach((g: string) => result.add(g));
        }
      }
    }
    return Array.from(result);
  }
}
