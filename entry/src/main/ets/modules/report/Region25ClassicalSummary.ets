/**
 * 二十五明堂色部 · 综合摘要（古籍体例）
 * 依据《灵枢·五色》等色诊用语，由 25 区结果合成整体结论，不含 Lab 数值
 */
import { Region25ColorItem, Region25SessionResult } from '../../common/types/AppTypes';

/** 五色频次排序项 */
interface ColorRankItem {
  color: string;
  count: number;
}

/** 上庭色部（心、肺、肝胆等） */
const UPPER_NAMES: string[] =
  ['天庭', '阙中', '山根', '右日角', '左日角', '右月角', '左月角', '右阙', '左阙'];
/** 中庭色部（脾胃等） */
const MIDDLE_NAMES: string[] =
  ['年上', '寿上', '准头', '右山根', '左山根', '右卧蚕', '左卧蚕', '右鼻翼', '左鼻翼'];
/** 下庭色部（肾、下焦等） */
const LOWER_NAMES: string[] =
  ['人中', '承浆', '地阁', '右颧骨', '左颧骨', '右法令', '左法令'];

/** 五色 → 古籍病机表述（《灵枢·五色》简表） */
const COLOR_CLASSICAL: Record<string, string> = {
  '青': '寒瘀',
  '赤': '热盛',
  '黄': '湿困',
  '白': '气虚',
  '黑': '寒凝'
};

export class Region25ClassicalSummary {
  /**
   * 生成用户可见的综合段落
   * 优先用 25 区数据现场合成；无区数据时回退服务端 summaryText（并剔除数值行）
   */
  static build(session: Region25SessionResult): string {
    if (session.regions.length >= 25) {
      return Region25ClassicalSummary.composeFromRegions(session.regions);
    }
    const fallback = Region25ClassicalSummary.stripTechnicalLines(session.summaryText.trim());
    if (fallback.length > 0) {
      return fallback;
    }
    return '暂无综合摘要，请查看下方二十五部分项。';
  }

  /** 剔除 Lab 基准等工程数值行 */
  private static stripTechnicalLines(text: string): string {
    const lines = text.split('\n');
    const kept: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      if (line.includes('L=') || line.includes('a*=') || line.includes('b*=')) {
        continue;
      }
      if (line.startsWith('偏色统计：') && line.includes('未见')) {
        continue;
      }
      kept.push(line);
    }
    return kept.join('\n\n');
  }

  private static composeFromRegions(regions: Region25ColorItem[]): string {
    const colorCounts = Region25ClassicalSummary.countColors(regions);
    const overall = Region25ClassicalSummary.buildOverallConclusion(regions, colorCounts);
    const fiveColors = Region25ClassicalSummary.buildFiveColorOverview(colorCounts);
    const upper = Region25ClassicalSummary.buildCourtParagraph('上庭', '上焦·心肺', UPPER_NAMES, regions);
    const middle = Region25ClassicalSummary.buildCourtParagraph('中庭', '中焦·脾胃', MIDDLE_NAMES, regions);
    const lower = Region25ClassicalSummary.buildCourtParagraph('下庭', '下焦·肾命', LOWER_NAMES, regions);
    const transmission = Region25ClassicalSummary.buildTransmission(regions);
    const classicHint = Region25ClassicalSummary.buildClassicHint(regions);

    const parts: string[] = [];
    parts.push(`【整体结论】\n${overall}`);
    parts.push(`【五色总象】\n${fiveColors}`);
    parts.push(`【三庭分论】\n${upper}\n\n${middle}\n\n${lower}`);
    parts.push(`【传变合参】\n${transmission}`);
    parts.push(`【典籍提示】\n${classicHint}`);
    return parts.join('\n\n');
  }

  private static countColors(regions: Region25ColorItem[]): Record<string, number> {
    const counts: Record<string, number> = { '青': 0, '赤': 0, '黄': 0, '白': 0, '黑': 0 };
    for (let i = 0; i < regions.length; i++) {
      const c = regions[i].dominantColor;
      if (counts[c] !== undefined) {
        if (c !== '白') {
          counts[c] = counts[c] + 1;
        } else if (regions[i].lustre === '枯槁' || regions[i].lustre === '略晦') {
          counts['白'] = counts['白'] + 1;
        }
      }
    }
    return counts;
  }

  private static buildOverallConclusion(regions: Region25ColorItem[], counts: Record<string, number>): string {
    const ranked = Region25ClassicalSummary.rankColors(counts);
    const lustreNote = Region25ClassicalSummary.summarizeLustre(regions);
    const floatNote = Region25ClassicalSummary.summarizeFloating(regions);

    if (ranked.length === 0) {
      return '据《灵枢·五色》观二十五明堂：诸部色象大体调匀，明润有泽，未见显著偏胜之色。' +
        '宜顺时调摄起居饮食，以保中和。此为古籍色诊文化自察参考，不作医事依据。';
    }

    const colorPhrase = ranked.map((item) => `${item.color}（${COLOR_CLASSICAL[item.color] ?? '偏象'}）`).join('、');
    const heatUpper = Region25ClassicalSummary.countCourtColor(regions, UPPER_NAMES, '赤');
    const heatMiddle = Region25ClassicalSummary.countCourtColor(regions, MIDDLE_NAMES, '赤');
    const dampLower = Region25ClassicalSummary.countCourtColor(regions, LOWER_NAMES, '黄');

    let trend = '';
    if (heatUpper >= 1 && heatMiddle >= 1) {
      trend = '上中二庭热象并见，有热势内传之虞；';
    }
    if (heatMiddle >= 1 && Region25ClassicalSummary.countCourtColor(regions, LOWER_NAMES, '青') +
      Region25ClassicalSummary.countCourtColor(regions, LOWER_NAMES, '黑') >= 1) {
      trend = trend + '中庭热象与下庭寒象相杂，寒热错杂；';
    }
    if (dampLower >= 3) {
      trend = trend + '下庭黄象偏盛，湿困趋于下焦；';
    }
    if (trend.length === 0) {
      trend = '三庭色象各有偏重而未成明显传变链；';
    }

    return `据《灵枢·五色》合参二十五明堂色部：全面色象以${colorPhrase}等偏盛为主。` +
      `${trend}${lustreNote}${floatNote}` +
      '合而观之，宜从起居、饮食、情志诸端慎为调摄。此为古籍养生文化自测参考，不作医事依据。';
  }

  private static buildFiveColorOverview(counts: Record<string, number>): string {
    const ranked = Region25ClassicalSummary.rankColors(counts);
    if (ranked.length === 0) {
      return '《灵枢·五色》以明润匀称为要：今观诸部大体符合，青赤黄白黑未见显著偏胜。';
    }
    const lines: string[] = [];
    lines.push('《灵枢·五色》曰：「五色必以明为准」；又曰：「青者肝象，赤者心象，黄者脾象，白者肺象，黑者肾象」。');
    for (let i = 0; i < ranked.length && i < 3; i++) {
      const item = ranked[i];
      lines.push(`今${item.color}色偏盛于${item.count}处，主${COLOR_CLASSICAL[item.color] ?? '偏象'}之候。`);
    }
    return lines.join('');
  }

  private static buildCourtParagraph(
    courtLabel: string,
    courtClassic: string,
    names: string[],
    regions: Region25ColorItem[]
  ): string {
    const courtRegions = Region25ClassicalSummary.filterByNames(regions, names);
    const notable = courtRegions.filter((r) =>
      r.dominantColor !== '白' || r.lustre !== '有泽' || r.scatterCluster === '抟'
    );

    if (notable.length === 0) {
      return `${courtLabel}（${courtClassic}）：诸部明润尚匀，色象平和。`;
    }

    const colorCounts: Record<string, number> = {};
    for (let i = 0; i < notable.length; i++) {
      const c = notable[i].dominantColor;
      colorCounts[c] = (colorCounts[c] ?? 0) + 1;
    }
    const topColors = Region25ClassicalSummary.rankFromMap(colorCounts).slice(0, 2);
    const colorText = topColors.map((t) => `${t.color}偏盛`).join('、');

    const regionNames: string[] = [];
    for (let i = 0; i < notable.length && i < 4; i++) {
      regionNames.push(notable[i].name);
    }
    const regionText = regionNames.join('、');

    let floatText = '';
    const floating = notable.filter((r) => r.floatingSinking === '浮').length;
    const sinking = notable.filter((r) => r.floatingSinking === '沉').length;
    if (floating > sinking && floating >= 2) {
      floatText = '，多色浮于外，象在表';
    } else if (sinking > floating && sinking >= 2) {
      floatText = '，多色沉于内，象在里';
    }

    let lustreText = '';
    const dry = notable.filter((r) => r.lustre === '枯槁' || r.lustre === '略晦').length;
    if (dry >= 2) {
      lustreText = '；部分色部光泽不足，宜慎养正气';
    }

    return `${courtLabel}（${courtClassic}）：${regionText}等部${colorText}${floatText}${lustreText}。`;
  }

  private static buildTransmission(regions: Region25ColorItem[]): string {
    const upperHeat = Region25ClassicalSummary.countCourtColor(regions, UPPER_NAMES, '赤');
    const middleHeat = Region25ClassicalSummary.countCourtColor(regions, MIDDLE_NAMES, '赤');
    const lowerCold = Region25ClassicalSummary.countCourtColor(regions, LOWER_NAMES, '青') +
      Region25ClassicalSummary.countCourtColor(regions, LOWER_NAMES, '黑');
    const hints: string[] = [];

    if (upperHeat >= 1 && middleHeat >= 1) {
      hints.push('上庭见赤，中庭亦赤，据色诊传变之说，热象有内传之势');
    }
    if (middleHeat >= 1 && lowerCold >= 1) {
      hints.push('中庭热象与下庭寒象并见，寒热相杂，宜合参调摄');
    }
    const scatterHeavy = regions.filter((r) => r.scatterCluster === '抟').length;
    const scatterLight = regions.filter((r) => r.scatterCluster === '散').length;
    if (scatterHeavy >= 5) {
      hints.push('多区色块凝聚，象偏「抟」，古以色抟者久病根深，宜久养');
    } else if (scatterLight >= 5) {
      hints.push('多区色象散漫，象偏「散」，古以色散者病轻或新起');
    }
    if (hints.length === 0) {
      hints.push('三庭色象各自偏重，未见显著上下传变链，宜分部位合参下方分项');
    }
    return hints.join('；') + '。';
  }

  private static buildClassicHint(regions: Region25ColorItem[]): string {
    const sinking = regions.filter((r) => r.floatingSinking === '沉').length;
    const floating = regions.filter((r) => r.floatingSinking === '浮').length;
    let quote = '《灵枢·五色》：「色沉者病在里，色浮者病在表。」';
    if (sinking > floating) {
      quote = quote + ' 今观沉象较多，合参当留意里象之养。';
    } else if (floating > sinking) {
      quote = quote + ' 今观浮象较多，合参当留意表象之调。';
    } else {
      quote = quote + ' 今观浮沉相当，宜表里兼顾。';
    }
    quote = quote + ' 《望诊遵经》亦强调以明堂明润、五色匀称为先。';
    return quote;
  }

  private static summarizeLustre(regions: Region25ColorItem[]): string {
    const dry = regions.filter((r) => r.lustre === '枯槁' || r.lustre === '略晦').length;
    if (dry >= 8) {
      return '多区晦暗枯槁，光泽不足，正气欠充；';
    }
    if (dry >= 3) {
      return '部分色部光泽略减；';
    }
    return '大部色部尚有润泽；';
  }

  private static summarizeFloating(regions: Region25ColorItem[]): string {
    const floating = regions.filter((r) => r.floatingSinking === '浮').length;
    const sinking = regions.filter((r) => r.floatingSinking === '沉').length;
    if (floating > sinking + 3) {
      return '浮象偏多，色在表者众；';
    }
    if (sinking > floating + 3) {
      return '沉象偏多，色在里者众；';
    }
    return '';
  }

  private static rankColors(counts: Record<string, number>): ColorRankItem[] {
    return Region25ClassicalSummary.rankFromMap(counts).filter((item) => item.count >= 2);
  }

  private static rankFromMap(map: Record<string, number>): ColorRankItem[] {
    const keys = Object.keys(map);
    const list: ColorRankItem[] = [];
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i];
      if (map[k] > 0) {
        const item: ColorRankItem = { color: k, count: map[k] };
        list.push(item);
      }
    }
    list.sort((a, b) => b.count - a.count);
    return list;
  }

  private static filterByNames(regions: Region25ColorItem[], names: string[]): Region25ColorItem[] {
    const out: Region25ColorItem[] = [];
    for (let i = 0; i < regions.length; i++) {
      if (names.indexOf(regions[i].name) >= 0) {
        out.push(regions[i]);
      }
    }
    return out;
  }

  private static countCourtColor(regions: Region25ColorItem[], names: string[], color: string): number {
    let n = 0;
    for (let i = 0; i < regions.length; i++) {
      if (names.indexOf(regions[i].name) >= 0 && regions[i].dominantColor === color) {
        n = n + 1;
      }
    }
    return n;
  }
}
