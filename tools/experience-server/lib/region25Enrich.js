/**
 * 25 色部报告扩展：古籍匹配 + 四维养护 + 文案解读（与 App / 网页版一致）
 */
const fs = require('fs');
const path = require('path');

const KNOWLEDGE_PATH = path.join(__dirname, '..', 'data', 'ancient_knowledge.json');
const CITATION_NOTICE =
  '以下均为所引古籍原文摘录，仅供您自行查阅原典、自行理解；' +
  '本应用不对原文作延伸解读，亦不提供个性化养护指导或用药建议。';

let knowledgeBaseCache = null;

function loadKnowledgeBase() {
  if (!knowledgeBaseCache) {
    knowledgeBaseCache = JSON.parse(fs.readFileSync(KNOWLEDGE_PATH, 'utf8'));
  }
  return knowledgeBaseCache;
}

function pickLine(lines, keyword, fallback) {
  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes(keyword)) return lines[i];
  }
  return fallback;
}

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
  rawTags.forEach((raw) => normalizeTag(String(raw)).forEach((t) => normalized.add(t)));
  return normalized;
}

function scoreEntry(entry, featureTags) {
  let score = 0;
  (entry.featureTags || []).forEach((entryTag) => {
    normalizeTag(entryTag).forEach((en) => {
      if (featureTags.has(en)) {
        score += HIGH_WEIGHT.has(en) ? 3 : 2;
      } else {
        for (const ft of featureTags) {
          if (ft.includes(en) || en.includes(ft)) {
            score += 1;
            break;
          }
        }
      }
    });
  });
  return score;
}

function matchFeatures(features, knowledgeBase, topN) {
  const featureTags = buildNormalizedTagSet(features);
  const scored = [];
  knowledgeBase.forEach((entry) => {
    const score = scoreEntry(entry, featureTags);
    if (score > 0) scored.push({ entry, score });
  });
  scored.sort((a, b) => b.score - a.score);
  let results = scored.slice(0, topN).map((s) => s.entry);
  if (results.length < 3) {
    knowledgeBase
      .filter((e) => (e.featureTags || []).includes('通用'))
      .forEach((ge) => {
        if (results.length >= topN) return;
        if (!results.some((r) => r.id === ge.id)) results.push(ge);
      });
  }
  return results.slice(0, topN);
}

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

const DIMENSION_KEYWORDS = {
  diet: ['食', '饮', '谷', '果', '畜', '菜', '味', '饱', '饥', '盐', '水', '润', '燥', '温', '冷', '生'],
  exercise: ['劳', '行', '动', '卧', '立', '坐', '筋', '肉', '骨', '气'],
  schedule: ['寝', '起', '睡', '夜', '早', '晚', '起居', '作', '时', '季', '藏'],
  emotion: ['情', '怒', '喜', '思', '忧', '恐', '躁', '静', '郁', '心'],
};

function detectComplexionKey(entries) {
  const allTags = [];
  entries.forEach((e) => allTags.push(...(e.featureTags || [])));
  if (allTags.some((t) => t.includes('偏白'))) return '偏白';
  if (allTags.some((t) => t.includes('偏黄'))) return '偏黄';
  if (allTags.some((t) => t.includes('偏红') || t.includes('泛红'))) return '偏红';
  if (allTags.some((t) => t.includes('偏暗沉') || t.includes('暗沉'))) return '偏暗沉';
  return '通用';
}

function matchesDimension(entry, dimension) {
  const text = (entry.originalText || '') + (entry.chapter || '');
  return (DIMENSION_KEYWORDS[dimension] || []).some((kw) => text.includes(kw));
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
  matched.forEach((entry) => {
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

function generateWellnessPlan(entries, knowledgeBase) {
  const entryMap = {};
  knowledgeBase.forEach((e) => {
    entryMap[e.id] = e;
  });
  const complexionKey = detectComplexionKey(entries);
  return {
    diet: pickCitations('diet', complexionKey, entries, entryMap, 3),
    exercise: pickCitations('exercise', complexionKey, entries, entryMap, 2),
    schedule: pickCitations('schedule', complexionKey, entries, entryMap, 3),
    emotion: pickCitations('emotion', complexionKey, entries, entryMap, 2),
    citationNotice: CITATION_NOTICE,
  };
}

function buildRagContext(entries) {
  return entries
    .map((e) => `【${e.source}·${e.chapter}】\n原文：${e.originalText}\n释义：${e.modernExplanation}`)
    .join('\n\n');
}

function buildUserPrompt(features, profileGender, ragContext) {
  const profileText = profileGender ? `用户基础信息：性别 ${profileGender}。\n` : '';
  return (
    `${profileText}` +
    `面部外观客观描述：${features.overallComplexion}；` +
    `${features.forehead}；${features.leftCheek}；${features.rightCheek}；` +
    `${features.nose}；${features.chin}；${features.eyeArea}；${features.lipArea}。\n\n` +
    `请结合以下古籍条目给出养生文化解读：\n${ragContext}`
  );
}

function buildOfflineInterpretation(entries) {
  const parts = ['（离线古籍解读）'];
  entries.forEach((entry) => {
    parts.push(
      `【${entry.source}·${entry.chapter}】\n原文：${entry.originalText}\n释义：${entry.modernExplanation}`
    );
  });
  return parts.join('\n\n');
}

/**
 * @param {object} colorReport Python 色诊 JSON
 * @param {string} profileGender 用户性别
 * @param {function|null} dashscopeChat async (body) => { status, body }
 */
async function buildReportExtras(colorReport, profileGender, dashscopeChat) {
  const knowledgeBase = loadKnowledgeBase();
  const features = toFaceAppearanceFeature(colorReport);
  const ancientEntries = matchFeatures(features, knowledgeBase, 5);
  const wellnessPlan = generateWellnessPlan(ancientEntries, knowledgeBase);

  let culturalInterpretation = buildOfflineInterpretation(ancientEntries);
  let usedOffline = true;

  if (typeof dashscopeChat === 'function') {
    const systemPrompt =
      '你是古籍养生文化解读助手。请基于提供的古籍原文与现代释义，' +
      '用通俗易懂的语言给出养生观察参考。严禁使用任何医疗、诊疗、用药相关表述，' +
      '仅输出文化娱乐与日常养护参考内容。';
    const userPrompt = buildUserPrompt(features, profileGender, buildRagContext(ancientEntries));
    try {
      const ds = await dashscopeChat({
        model: 'qwen-turbo',
        temperature: 0.7,
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt },
        ],
      });
      if (ds.status >= 200 && ds.status < 300) {
        const parsed = JSON.parse(ds.body);
        const content = (parsed.choices?.[0]?.message?.content || '').trim();
        if (content) {
          culturalInterpretation = `（体验免 Key 解读）\n${content}`;
          usedOffline = false;
        }
      }
    } catch (_e) {
      /* 保持离线解读 */
    }
  }

  return { culturalInterpretation, ancientEntries, wellnessPlan, usedOffline };
}

module.exports = { buildReportExtras };
