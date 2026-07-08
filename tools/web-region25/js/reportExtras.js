/**
 * 报告扩展：古人养生解读、古籍溯源、四维养护（与鸿蒙 App 报告页一致）
 */
(function (global) {
  let knowledgeBasePromise = null;

  function loadKnowledgeBase() {
    if (!knowledgeBasePromise) {
      knowledgeBasePromise = fetch('/sezhen/data/ancient_knowledge.json')
        .then((res) => {
          if (!res.ok) throw new Error('古籍知识库加载失败');
          return res.json();
        });
    }
    return knowledgeBasePromise;
  }

  function buildRagContext(entries) {
    return (entries || [])
      .map(
        (e) =>
          `【${e.source}·${e.chapter}】\n原文：${e.originalText}\n释义：${e.modernExplanation}`
      )
      .join('\n\n');
  }

  function buildUserPrompt(features, profileGender, ragContext) {
    const profileText =
      profileGender && profileGender !== '未设置' ? `用户基础信息：性别 ${profileGender}。\n` : '';
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
    (entries || []).forEach((entry) => {
      parts.push(
        `【${entry.source}·${entry.chapter}】\n原文：${entry.originalText}\n释义：${entry.modernExplanation}`
      );
    });
    return parts.join('\n\n');
  }

  /**
   * 生成扩展报告内容
   * @param {object} colorReport 色诊 JSON
   * @param {string} profileGender 用户性别
   * @param {function} apiPost 已鉴权的 POST 方法
   */
  async function buildReportExtras(colorReport, profileGender, apiPost) {
    const knowledgeBase = await loadKnowledgeBase();
    const features = global.Region25FeatureMapper.toFaceAppearanceFeature(colorReport);
    const ancientEntries = global.KnowledgeMatchEngine.matchFeatures(features, knowledgeBase, 5);
    const wellnessPlan = global.WellnessPlanBuilder.generatePlan(ancientEntries, knowledgeBase);

    const systemPrompt =
      '你是古籍养生文化解读助手。请基于提供的古籍原文与现代释义，' +
      '用通俗易懂的语言给出养生观察参考。严禁使用任何医疗、诊疗、用药相关表述，' +
      '仅输出文化娱乐与日常养护参考内容。';
    const userPrompt = buildUserPrompt(features, profileGender, buildRagContext(ancientEntries));

    let culturalInterpretation = '';
    let usedOffline = true;
    try {
      const data = await apiPost('/v1/text/generate', { systemPrompt, userPrompt });
      if (data.content && String(data.content).trim()) {
        culturalInterpretation = `（体验免 Key 解读）\n${String(data.content).trim()}`;
        usedOffline = false;
      }
    } catch (_e) {
      /* 文案 API 不可用时走离线古籍拼接 */
    }
    if (!culturalInterpretation) {
      culturalInterpretation = buildOfflineInterpretation(ancientEntries);
    }

    return { culturalInterpretation, ancientEntries, wellnessPlan, usedOffline };
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function renderAncientReferences(container, entries) {
    if (!container) return;
    container.innerHTML = '';
    if (!entries || entries.length === 0) {
      container.innerHTML = '<p class="meta">暂无匹配古籍条目</p>';
      return;
    }
    entries.forEach((entry) => {
      const card = document.createElement('article');
      card.className = 'ancient-card';
      card.innerHTML =
        `<p class="ancient-source">${escapeHtml(entry.source)} · ${escapeHtml(entry.chapter)}</p>` +
        `<div class="ancient-original"><span class="ancient-label">【古籍原文】</span>${escapeHtml(entry.originalText)}</div>` +
        `<div class="ancient-modern"><span class="ancient-label">【白话释义】</span>${escapeHtml(entry.modernExplanation)}</div>`;
      container.appendChild(card);
    });
  }

  function renderCitationSection(parent, title, icon, items) {
    const block = document.createElement('div');
    block.className = 'wellness-section';
    const head = document.createElement('p');
    head.className = 'wellness-section-title';
    head.textContent = `${icon} ${title}`;
    block.appendChild(head);
    if (!items || items.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'meta';
      empty.textContent = '暂无对应古籍摘录';
      block.appendChild(empty);
    } else {
      items.forEach((item, index) => {
        const row = document.createElement('div');
        row.className = 'wellness-citation';
        row.innerHTML =
          `<p class="wellness-citation-src">${index + 1}. ${escapeHtml(item.source)} · ${escapeHtml(item.chapter)}</p>` +
          `<p class="wellness-citation-text">「${escapeHtml(item.originalText)}」</p>`;
        block.appendChild(row);
      });
    }
    parent.appendChild(block);
  }

  function renderWellnessPlan(container, plan) {
    if (!container) return;
    container.innerHTML = '';
    if (!plan) {
      container.innerHTML = '<p class="meta">暂无养护方案</p>';
      return;
    }
    const notice = document.createElement('p');
    notice.className = 'wellness-notice';
    notice.textContent = plan.citationNotice || '';
    container.appendChild(notice);
    renderCitationSection(container, '饮食 · 古籍原文', '🍵', plan.diet);
    renderCitationSection(container, '运动 · 古籍原文', '🏃', plan.exercise);
    renderCitationSection(container, '作息 · 古籍原文', '🌙', plan.schedule);
    renderCitationSection(container, '情绪 · 古籍原文', '🧘', plan.emotion);
  }

  function renderCulturalInterpretation(container, text) {
    if (!container) return;
    container.textContent = text || '暂无解读内容';
  }

  global.ReportExtras = {
    buildReportExtras,
    renderAncientReferences,
    renderWellnessPlan,
    renderCulturalInterpretation,
  };
})(typeof window !== 'undefined' ? window : global);
