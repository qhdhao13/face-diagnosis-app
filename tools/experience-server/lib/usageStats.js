/**
 * 体验服使用统计（从各 session 的 meta.json 与 tokens.json 汇总）
 */
const fs = require('fs');
const path = require('path');

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_e) {
    return fallback;
  }
}

function maskPhone(phone) {
  if (typeof phone !== 'string' || phone.length !== 11) {
    return phone || '—';
  }
  return `${phone.slice(0, 3)}****${phone.slice(7)}`;
}

function dayKeyFromMs(ms) {
  const d = new Date(ms);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/**
 * @param {object} opts
 * @param {string} opts.dataDir - experience-server/data 目录
 * @param {number} opts.days - 统计最近 N 天（含今天）
 * @param {boolean} opts.maskPhones - 是否脱敏手机号
 */
function buildUsageStats(opts) {
  const dataDir = opts.dataDir;
  const days = Math.max(1, parseInt(String(opts.days || 30), 10));
  const maskPhones = opts.maskPhones !== false;

  const sessionsDir = path.join(dataDir, 'sessions');
  const tokensFile = path.join(dataDir, 'tokens.json');
  const quotaFile = path.join(dataDir, 'quota.json');

  const now = Date.now();
  const sinceMs = now - (days - 1) * 86400000;
  const sinceDay = dayKeyFromMs(sinceMs);

  /** @type {Array<{sessionId:string, phone:string, createdAt:number, day:string}>} */
  const allSessions = [];

  if (fs.existsSync(sessionsDir)) {
    const dirs = fs.readdirSync(sessionsDir, { withFileTypes: true });
    dirs.forEach((ent) => {
      if (!ent.isDirectory()) {
        return;
      }
      const metaPath = path.join(sessionsDir, ent.name, 'meta.json');
      if (!fs.existsSync(metaPath)) {
        return;
      }
      try {
        const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
        const createdAt = Number(meta.createdAt) || 0;
        const phone = String(meta.phone || '').trim();
        if (createdAt <= 0 || phone.length !== 11) {
          return;
        }
        allSessions.push({
          sessionId: ent.name,
          phone,
          createdAt,
          day: dayKeyFromMs(createdAt)
        });
      } catch (_e) {
        // 跳过损坏的 meta
      }
    });
  }

  allSessions.sort((a, b) => b.createdAt - a.createdAt);

  const inRange = allSessions.filter((s) => s.day >= sinceDay);

  // 按日：分析次数、独立用户数
  const byDayMap = {};
  inRange.forEach((s) => {
    if (!byDayMap[s.day]) {
      byDayMap[s.day] = { date: s.day, analyses: 0, uniquePhones: new Set() };
    }
    byDayMap[s.day].analyses += 1;
    byDayMap[s.day].uniquePhones.add(s.phone);
  });

  const byDay = Object.keys(byDayMap)
    .sort()
    .map((k) => ({
      date: k,
      analyses: byDayMap[k].analyses,
      uniqueUsers: byDayMap[k].uniquePhones.size
    }));

  const uniqueUsersInRange = new Set(inRange.map((s) => s.phone));

  // 注册 token 中的独立手机号（含注册但未分析的用户）
  const tokens = readJson(tokensFile, {});
  const registeredPhones = new Set(
    Object.values(tokens).filter((p) => typeof p === 'string' && p.length === 11)
  );

  const quotaMap = readJson(quotaFile, {});
  const today = dayKeyFromMs(now);
  let todayAnalysesFromQuota = 0;
  Object.keys(quotaMap).forEach((phone) => {
    const rec = quotaMap[phone];
    if (rec && rec.date === today && typeof rec.used === 'number') {
      todayAnalysesFromQuota += rec.used;
    }
  });

  const formatPhone = (p) => (maskPhones ? maskPhone(p) : p);

  return {
    ok: true,
    generatedAt: now,
    rangeDays: days,
    rangeFrom: sinceDay,
    rangeTo: today,
    summary: {
      /** 时间范围内至少完成 1 次色诊分析的去重手机号 */
      uniqueUsersWithAnalysis: uniqueUsersInRange.size,
      /** 时间范围内色诊分析总次数（每次分析 1 个 session） */
      totalAnalyses: inRange.length,
      /** 当前 tokens 中去重注册手机号（含未分析） */
      registeredPhonesTotal: registeredPhones.size,
      /** 全库 session 总数（不限时间） */
      allTimeSessionCount: allSessions.length,
      /** 今日 quota 累计扣次（与 session 可能略有偏差，供交叉核对） */
      todayAnalysesFromQuota
    },
    byDay,
    recentSessions: inRange.slice(0, 20).map((s) => ({
      sessionId: s.sessionId,
      phone: formatPhone(s.phone),
      createdAt: s.createdAt,
      day: s.day
    }))
  };
}

module.exports = { buildUsageStats, maskPhone, dayKeyFromMs };
