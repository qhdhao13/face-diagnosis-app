/**
 * 面部外观观察报告格式化
 * 按古籍面部分区（上庭/中庭/下庭、五官）排版，参照《灵枢·五色》《望诊遵经》观象用语
 */
import { FaceAppearanceFeature } from '../../common/types/AppTypes';
import { AncientSources } from '../../common/constants/AppConstants';

export class AppearanceSummaryFormatter {
  /** 格式化为分区、分段的古籍风格观察报告 */
  static format(features: FaceAppearanceFeature): string {
    const lines: string[] = [];

    lines.push('【整体观色·五色象】');
    lines.push(
      `整体面色${features.overallComplexion}。` +
      `古人${AncientSources.LINGSHU_WUSE}以「明润、匀净」为常象，` +
      '此处为外观气色之文化观察，仅供养生自测参考，非医疗结论。'
    );

    lines.push('');
    lines.push('【上庭·天庭额部】');
    lines.push(AppearanceSummaryFormatter.formatRegion(
      features.forehead,
      '天庭',
      '额部明润尚匀，未见显著枯槁或晦暗之色'
    ));

    lines.push('');
    lines.push('【中庭·颧颊两部】');
    lines.push(`左颊：${AppearanceSummaryFormatter.stripRegionPrefix(features.leftCheek, '左脸颊')}`);
    lines.push(`右颊：${AppearanceSummaryFormatter.stripRegionPrefix(features.rightCheek, '右脸颊')}`);

    lines.push('');
    lines.push('【五官·目鼻唇】');
    lines.push(`目：${AppearanceSummaryFormatter.stripRegionPrefix(features.eyeArea, '眼周')}`);
    lines.push(`鼻：${AppearanceSummaryFormatter.stripRegionPrefix(features.nose, '鼻部')}`);
    lines.push(`唇：${AppearanceSummaryFormatter.formatLip(features.lipArea)}`);

    lines.push('');
    lines.push('【下庭·地阁颏部】');
    lines.push(AppearanceSummaryFormatter.formatRegion(
      features.chin,
      '地阁',
      '下颏轮廓尚清，色泽与面中相称'
    ));

    if (features.details.length > 0) {
      lines.push('');
      lines.push('【细察补充】');
      for (const detail of features.details) {
        lines.push(`· ${detail}`);
      }
    }

    return lines.join('\n');
  }

  /** 单区描述：过短时套用古籍观象句式补全 */
  private static formatRegion(raw: string, ancientName: string, defaultDesc: string): string {
    const body = AppearanceSummaryFormatter.stripRegionPrefix(raw, ancientName);
    if (body.length >= 18) {
      return `${ancientName}：${body}`;
    }
    const complexion = AppearanceSummaryFormatter.extractComplexionTag(body);
    if (complexion.length > 0) {
      return `${ancientName}：见${complexion}之象，${defaultDesc}，${body}`;
    }
    return `${ancientName}：${defaultDesc}，${body}`;
  }

  /** 唇区专用（古籍称「唇珠」「口唇」） */
  private static formatLip(raw: string): string {
    const body = AppearanceSummaryFormatter.stripRegionPrefix(raw, '唇');
    if (body.length >= 12) {
      return body;
    }
    return `口唇${body}，唇线尚清，为古人观唇之常象`;
  }

  /** 去掉「额头：」「左脸颊：」等重复前缀，保留实质描述 */
  private static stripRegionPrefix(text: string, regionHint: string): string {
    let result = text.trim();
    const prefixes: string[] = [
      `${regionHint}：`, `${regionHint}:`, '左脸颊：', '右脸颊：', '左颊：', '右颊：',
      '额头：', '天庭：', '鼻部：', '明堂：', '下巴：', '地阁：', '眼周：', '目：', '唇：'
    ];
    for (const prefix of prefixes) {
      if (result.startsWith(prefix)) {
        result = result.substring(prefix.length).trim();
        break;
      }
    }
    if (result.length === 0) {
      return '色泽尚匀，未见显著异常';
    }
    return result;
  }

  /** 从短描述中提取气色词（封闭词表内常见字） */
  private static extractComplexionTag(text: string): string {
    const tags: string[] = [
      '偏白', '偏黄', '偏红', '偏暗沉', '偏青白', '暗沉', '泛红', '浮肿', '细纹', '气色尚可'
    ];
    for (const tag of tags) {
      if (text.indexOf(tag) >= 0) {
        return tag;
      }
    }
    return '';
  }
}
