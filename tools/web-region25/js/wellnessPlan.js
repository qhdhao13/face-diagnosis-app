/**
 * 四维养护方案 · 古籍原文摘录（与 App WellnessAncientCatalog 一致）
 */
(function (global) {
  const CITATION_NOTICE =
    '以下均为所引古籍原文摘录，仅供您自行查阅原典、自行理解；' +
    '本应用不对原文作延伸解读，亦不提供个性化养护指导或用药建议。';

  const DIMENSION_KEYWORDS = {
    diet: ['食', '饮', '谷', '果', '畜', '菜', '味', '饱', '饥', '盐', '水', '润', '燥', '温', '冷', '生'],
    exercise: ['劳', '行', '动', '卧', '立', '坐', '筋', '肉', '骨', '气'],
    schedule: ['寝', '起', '睡', '夜', '早', '晚', '起居', '作', '时', '季', '藏'],
    emotion: ['情', '怒', '喜', '思', '忧', '恐', '躁', '静', '郁', '心'],
  };

  const CATALOG = {
    diet: {
      偏白: ['ls008', 'wh005', 'general005', 'wz003'],
      偏黄: ['ls009', 'wh006', 'general005', 'ls001'],
      偏红: ['ls010', 'wh007', 'wz003', 'wz008'],
      偏暗沉: ['wh008', 'wz010', 'wh003', 'ls006'],
      通用: ['general005', 'general001', 'wh001', 'ls007'],
    },
    exercise: {
      偏白: ['general004', 'wh005', 'general002'],
      偏黄: ['general004', 'ls009', 'general002'],
      偏红: ['general004', 'ls003', 'wh007'],
      偏暗沉: ['general004', 'wh002', 'ls007'],
      通用: ['general004', 'general002', 'wh001'],
    },
    schedule: {
      偏白: ['ls002', 'general001', 'wz007', 'wh004'],
      偏黄: ['general001', 'ls009', 'general002'],
      偏红: ['ls003', 'ls010', 'wh007'],
      偏暗沉: ['wz004', 'ls006', 'wh004', 'wz009'],
      通用: ['general001', 'general002', 'ls007', 'wh011'],
    },
    emotion: {
      偏白: ['general003', 'wz007', 'wh011'],
      偏黄: ['general003', 'wz001', 'wh001'],
      偏红: ['ls003', 'ls010', 'general003', 'wz005'],
      偏暗沉: ['general003', 'ls004', 'wh004', 'wh010'],
      通用: ['general003', 'wh001', 'wz005'],
    },
  };

  function buildEntryMap(knowledgeBase) {
    const map = {};
    (knowledgeBase || []).forEach((e) => {
      map[e.id] = e;
    });
    return map;
  }

  function detectComplexionKey(entries) {
    const allTags = [];
    (entries || []).forEach((e) => allTags.push(...(e.featureTags || [])));
    if (allTags.some((t) => t.includes('偏白'))) return '偏白';
    if (allTags.some((t) => t.includes('偏黄'))) return '偏黄';
    if (allTags.some((t) => t.includes('偏红') || t.includes('泛红'))) return '偏红';
    if (allTags.some((t) => t.includes('偏暗沉') || t.includes('暗沉'))) return '偏暗沉';
    return '通用';
  }

  function matchesDimension(entry, dimension) {
    const text = (entry.originalText || '') + (entry.chapter || '');
    return (DIMENSION_KEYWORDS[dimension] || []).some((kw) => text.indexOf(kw) >= 0);
  }

  function toCitation(entry) {
    return {
      entryId: entry.id,
      source: entry.source,
      chapter: entry.chapter,
      originalText: entry.originalText,
    };
  }

  function pickCitations(dimension, complexionKey, matched, entryMap, maxCount) {
    const result = [];
    const used = new Set();
    (matched || []).forEach((entry) => {
      if (result.length >= maxCount) return;
      if (matchesDimension(entry, dimension) && !used.has(entry.id)) {
        result.push(toCitation(entry));
        used.add(entry.id);
      }
    });
    const ids = (CATALOG[dimension] && CATALOG[dimension][complexionKey]) || CATALOG[dimension].通用;
    ids.forEach((id) => {
      if (result.length >= maxCount) return;
      if (used.has(id)) return;
      const entry = entryMap[id];
      if (entry) {
        result.push(toCitation(entry));
        used.add(id);
      }
    });
    return result;
  }

  function generatePlan(entries, knowledgeBase) {
    const entryMap = buildEntryMap(knowledgeBase);
    const complexionKey = detectComplexionKey(entries);
    return {
      diet: pickCitations('diet', complexionKey, entries, entryMap, 3),
      exercise: pickCitations('exercise', complexionKey, entries, entryMap, 2),
      schedule: pickCitations('schedule', complexionKey, entries, entryMap, 3),
      emotion: pickCitations('emotion', complexionKey, entries, entryMap, 2),
      citationNotice: CITATION_NOTICE,
    };
  }

  global.WellnessPlanBuilder = { generatePlan };
})(typeof window !== 'undefined' ? window : global);
