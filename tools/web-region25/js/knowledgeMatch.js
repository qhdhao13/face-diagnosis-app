/**
 * 古籍知识库评分匹配（与 App KnowledgeMatchEngine 一致）
 */
(function (global) {
  const SYNONYM_GROUPS = [
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
    ['通用', '整体', '总则'],
  ];

  const HIGH_WEIGHT = new Set(['偏白', '偏黄', '偏红', '偏暗沉', '偏青白', '泛红', '通用']);

  function normalizeTag(raw) {
    const result = new Set([raw]);
    SYNONYM_GROUPS.forEach((group) => {
      group.forEach((synonym) => {
        if (raw.includes(synonym) || synonym.includes(raw)) {
          group.forEach((g) => result.add(g));
        }
      });
    });
    return Array.from(result);
  }

  function buildNormalizedTagSet(features) {
    const rawTags = [
      features.overallComplexion,
      features.forehead,
      features.leftCheek,
      features.rightCheek,
      features.nose,
      features.chin,
      features.eyeArea,
      features.lipArea,
      ...(features.details || []),
      ...(features.matchTags || []),
    ];
    const normalized = new Set();
    rawTags.forEach((raw) => {
      normalizeTag(String(raw)).forEach((t) => normalized.add(t));
    });
    return normalized;
  }

  function scoreEntry(entry, featureTags) {
    let score = 0;
    (entry.featureTags || []).forEach((entryTag) => {
      normalizeTag(entryTag).forEach((en) => {
        if (featureTags.has(en)) {
          score += HIGH_WEIGHT.has(en) ? 3 : 2;
        } else {
          featureTags.forEach((ft) => {
            if (ft.includes(en) || en.includes(ft)) score += 1;
          });
        }
      });
    });
    return score;
  }

  /** 返回 Top N 古籍条目 */
  function matchFeatures(features, knowledgeBase, topN) {
    const featureTags = buildNormalizedTagSet(features);
    const scored = [];
    (knowledgeBase || []).forEach((entry) => {
      const score = scoreEntry(entry, featureTags);
      if (score > 0) scored.push({ entry, score });
    });
    scored.sort((a, b) => b.score - a.score);
    let results = scored.slice(0, topN).map((s) => s.entry);

    if (results.length < 3) {
      const generalPool = (knowledgeBase || []).filter((e) => (e.featureTags || []).includes('通用'));
      generalPool.forEach((ge) => {
        if (results.length >= topN) return;
        if (!results.some((r) => r.id === ge.id)) results.push(ge);
      });
    }
    return results.slice(0, topN);
  }

  global.KnowledgeMatchEngine = { matchFeatures };
})(typeof window !== 'undefined' ? window : global);
