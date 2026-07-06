/**
 * 25色部云端报告 → FaceAppearanceFeature 映射
 * 供古籍知识库与报告摘要使用（算法层仍为 25 区独立分析）
 */
import { FaceAppearanceFeature, Region25ColorItem, Region25SessionResult } from '../../common/types/AppTypes';

export class Region25FeatureMapper {
  /** 内部用：从 25 区映射为 8 字段，供知识库/文案匹配（不在报告页展示八区排版） */
  static toFaceAppearanceFeature(session: Region25SessionResult, brightness: number): FaceAppearanceFeature {
    const lines = session.lineItems;
    const pick = (keyword: string, fallback: string): string => {
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].indexOf(keyword) >= 0) {
          return lines[i];
        }
      }
      return fallback;
    };

    const overall = Region25FeatureMapper.resolveOverallComplexion(session.regions);

    return {
      overallComplexion: overall,
      forehead: pick('天庭', pick('日角', '上庭色象见二十五色部分项')),
      leftCheek: pick('左颧骨', pick('左卧蚕', '左颧颊色象见分项')),
      rightCheek: pick('右颧骨', pick('右卧蚕', '右颧颊色象见分项')),
      nose: pick('准头', pick('山根', '鼻区色象见分项')),
      chin: pick('地阁', pick('承浆', '下庭色象见分项')),
      eyeArea: pick('卧蚕', '目眶区色象见分项'),
      lipArea: pick('人中', '口周色象见分项'),
      details: session.lineItems.slice(0, 4),
      confidence: 0.85,
      averageBrightness: brightness,
      matchTags: Region25FeatureMapper.buildMatchTags(session.regions, overall),
      analysisEngine: 'region25_cloud'
    };
  }

  private static resolveOverallComplexion(regions: Region25ColorItem[]): string {
    const counts: Map<string, number> = new Map();
    for (let i = 0; i < regions.length; i++) {
      const c = regions[i].dominantColor;
      counts.set(c, (counts.get(c) ?? 0) + 1);
    }
    const chi = counts.get('赤') ?? 0;
    const huang = counts.get('黄') ?? 0;
    const qing = counts.get('青') ?? 0;
    const hei = counts.get('黑') ?? 0;
    if (chi >= 3) {
      return '偏红';
    }
    if (huang >= 3) {
      return '偏黄';
    }
    if (qing >= 2 || hei >= 2) {
      return '偏暗沉';
    }
    return '气色尚可';
  }

  private static buildMatchTags(regions: Region25ColorItem[], overall: string): string[] {
    const tags: string[] = [];
    if (overall.length > 0) {
      tags.push(overall);
    }
    for (let i = 0; i < regions.length; i++) {
      const r = regions[i];
      if (r.dominantColor === '赤' && tags.indexOf('泛红') < 0) {
        tags.push('泛红');
      }
      if (r.lustre === '枯槁' && tags.indexOf('暗沉') < 0) {
        tags.push('暗沉');
      }
    }
    if (tags.length === 0) {
      tags.push('气色尚可');
    }
    return tags;
  }
}
