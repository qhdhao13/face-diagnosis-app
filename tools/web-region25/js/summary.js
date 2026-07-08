/**
 * 二十五明堂 · 古籍体例综合摘要（与 App 端逻辑一致）
 */
(function (global) {
  const UPPER = ['天庭', '阙中', '山根', '右日角', '左日角', '右月角', '左月角', '右阙', '左阙'];
  const MIDDLE = ['年上', '寿上', '准头', '右山根', '左山根', '右卧蚕', '左卧蚕', '右鼻翼', '左鼻翼'];
  const LOWER = ['人中', '承浆', '地阁', '右颧骨', '左颧骨', '右法令', '左法令'];
  const COLOR_CLASSICAL = { 青: '寒瘀', 赤: '热盛', 黄: '湿困', 白: '气虚', 黑: '寒凝' };

  function countColors(regions) {
    const counts = { 青: 0, 赤: 0, 黄: 0, 白: 0, 黑: 0 };
    regions.forEach((r) => {
      const c = r.dominant_color || r.dominantColor || '白';
      if (counts[c] !== undefined) {
        if (c !== '白') counts[c]++;
        else if (r.lustre === '枯槁' || r.lustre === '略晦') counts['白']++;
      }
    });
    return counts;
  }

  function rankColors(counts, minCount) {
    return Object.keys(counts)
      .filter((k) => counts[k] >= (minCount || 2))
      .map((k) => ({ color: k, count: counts[k] }))
      .sort((a, b) => b.count - a.count);
  }

  function countCourt(regions, names, color) {
    return regions.filter((r) => names.includes(r.name) && (r.dominant_color || r.dominantColor) === color).length;
  }

  function buildOverall(regions, counts) {
    const ranked = rankColors(counts);
    const dry = regions.filter((r) => r.lustre === '枯槁' || r.lustre === '略晦').length;
    const lustre = dry >= 8 ? '多区晦暗枯槁，光泽不足，正气欠充；' : dry >= 3 ? '部分色部光泽略减；' : '大部色部尚有润泽；';
    if (ranked.length === 0) {
      return '据《灵枢·五色》观二十五明堂：诸部色象大体调匀，明润有泽，未见显著偏胜之色。宜顺时调摄起居饮食，以保中和。此为古籍色诊文化自察参考，不作医事依据。';
    }
    const colorPhrase = ranked.slice(0, 3).map((x) => `${x.color}（${COLOR_CLASSICAL[x.color] || '偏象'}）`).join('、');
    let trend = '';
    if (countCourt(regions, UPPER, '赤') >= 1 && countCourt(regions, MIDDLE, '赤') >= 1) trend += '上中二庭热象并见，有热势内传之虞；';
    if (countCourt(regions, MIDDLE, '赤') >= 1 && countCourt(regions, LOWER, '青') + countCourt(regions, LOWER, '黑') >= 1) trend += '中庭热象与下庭寒象相杂，寒热错杂；';
    if (countCourt(regions, LOWER, '黄') >= 3) trend += '下庭黄象偏盛，湿困趋于下焦；';
    if (!trend) trend = '三庭色象各有偏重而未成明显传变链；';
    return `据《灵枢·五色》合参二十五明堂色部：全面色象以${colorPhrase}等偏盛为主。${trend}${lustre}合而观之，宜从起居、饮食、情志诸端慎为调摄。此为古籍养生文化自测参考，不作医事依据。`;
  }

  function courtPara(label, classic, names, regions) {
    const court = regions.filter((r) => names.includes(r.name));
    const notable = court.filter(
      (r) => (r.dominant_color || r.dominantColor) !== '白' || r.lustre !== '有泽' || r.scatter_cluster === '抟'
    );
    if (notable.length === 0) return `${label}（${classic}）：诸部明润尚匀，色象平和。`;
    const cc = {};
    notable.forEach((r) => {
      const c = r.dominant_color || r.dominantColor;
      cc[c] = (cc[c] || 0) + 1;
    });
    const top = Object.keys(cc).sort((a, b) => cc[b] - cc[a]).slice(0, 2);
    const names4 = notable.slice(0, 4).map((r) => r.name).join('、');
    return `${label}（${classic}）：${names4}等部${top.map((c) => c + '偏盛').join('、')}。`;
  }

  function buildClassicalSummary(colorReport) {
    if (!colorReport) return '暂无综合摘要。';
    const regions = colorReport.regions || [];
    const serverText = (colorReport.summary && colorReport.summary.summary_text) || '';
    if (serverText && !serverText.includes('L=') && serverText.includes('【整体结论】')) {
      return serverText;
    }
    if (regions.length < 25) return serverText || '暂无综合摘要。';
    const counts = countColors(regions);
    const parts = [
      '【整体结论】\n' + buildOverall(regions, counts),
      '【三庭分论】\n' + courtPara('上庭', '上焦·心肺', UPPER, regions) + '\n\n' +
        courtPara('中庭', '中焦·脾胃', MIDDLE, regions) + '\n\n' +
        courtPara('下庭', '下焦·肾命', LOWER, regions),
    ];
    return parts.join('\n\n');
  }

  global.buildClassicalSummary = buildClassicalSummary;
})(typeof window !== 'undefined' ? window : global);
