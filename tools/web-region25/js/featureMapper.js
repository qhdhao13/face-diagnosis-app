/**
 * 25 色部报告 → 面部特征映射（与 App Region25FeatureMapper 一致）
 */
(function (global) {
  function resolveOverallComplexion(regions) {
    const counts = { 青: 0, 赤: 0, 黄: 0, 白: 0, 黑: 0 };
    (regions || []).forEach((r) => {
      const c = r.dominant_color || r.dominantColor || '白';
      if (counts[c] !== undefined) counts[c]++;
    });
    if (counts['赤'] >= 3) return '偏红';
    if (counts['黄'] >= 3) return '偏黄';
    if (counts['青'] >= 2 || counts['黑'] >= 2) return '偏暗沉';
    return '气色尚可';
  }

  function buildMatchTags(regions, overall) {
    const tags = overall ? [overall] : [];
    (regions || []).forEach((r) => {
      const c = r.dominant_color || r.dominantColor;
      if (c === '赤' && !tags.includes('泛红')) tags.push('泛红');
      if (r.lustre === '枯槁' && !tags.includes('暗沉')) tags.push('暗沉');
    });
    if (tags.length === 0) tags.push('气色尚可');
    return tags;
  }

  function pickLine(lines, keyword, fallback) {
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].indexOf(keyword) >= 0) return lines[i];
    }
    return fallback;
  }

  /** 从 colorReport 构造知识库匹配用特征 */
  function toFaceAppearanceFeature(colorReport) {
    const lineItems = colorReport.line_items || colorReport.lineItems || [];
    const regions = colorReport.regions || [];
    const overall = resolveOverallComplexion(regions);

    return {
      overallComplexion: overall,
      forehead: pickLine(lineItems, '天庭', pickLine(lineItems, '日角', '上庭色象见二十五色部分项')),
      leftCheek: pickLine(lineItems, '左颧骨', pickLine(lineItems, '左卧蚕', '左颧颊色象见分项')),
      rightCheek: pickLine(lineItems, '右颧骨', pickLine(lineItems, '右卧蚕', '右颧颊色象见分项')),
      nose: pickLine(lineItems, '准头', pickLine(lineItems, '山根', '鼻区色象见分项')),
      chin: pickLine(lineItems, '地阁', pickLine(lineItems, '承浆', '下庭色象见分项')),
      eyeArea: pickLine(lineItems, '卧蚕', '目眶区色象见分项'),
      lipArea: pickLine(lineItems, '人中', '口周色象见分项'),
      details: lineItems.slice(0, 4),
      matchTags: buildMatchTags(regions, overall),
    };
  }

  global.Region25FeatureMapper = { toFaceAppearanceFeature };
})(typeof window !== 'undefined' ? window : global);
