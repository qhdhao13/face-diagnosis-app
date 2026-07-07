/**
 * 体验免 Key 代理服务
 * - 手机号注册 + 白名单
 * - 白名单用户每日 2 次完整自测（视觉请求时扣减）
 * - DashScope Key 仅存环境变量，不下发 App
 *
 * 启动：
 *   cd tools/experience-server
 *   npm install
 *   DASHSCOPE_API_KEY=sk-xxx npm start
 *   白名单：编辑 whitelist.json，或 WHITELIST=138xxx,139xxx
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { buildUsageStats } = require('./lib/usageStats');

const PORT = process.env.PORT || 8787;
const DASHSCOPE_KEY = process.env.DASHSCOPE_API_KEY || '';
const DAILY_LIMIT = parseInt(process.env.DAILY_FREE_LIMIT || '2', 10);

function loadWhitelistConfig() {
  const phones = [];
  const limits = {};

  const fromEnv = (process.env.WHITELIST || '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length === 11);
  if (fromEnv.length > 0) {
    fromEnv.forEach((phone) => {
      phones.push(phone);
      limits[phone] = DAILY_LIMIT;
    });
    return { phones, limits };
  }

  const filePath = path.join(__dirname, 'whitelist.json');
  try {
    const raw = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    if (Array.isArray(raw.entries)) {
      raw.entries.forEach((item) => {
        if (!item || typeof item.phone !== 'string' || item.phone.length !== 11) {
          return;
        }
        phones.push(item.phone);
        limits[item.phone] = parseInt(String(item.dailyLimit || DAILY_LIMIT), 10) || DAILY_LIMIT;
      });
    } else if (Array.isArray(raw.phones)) {
      raw.phones.forEach((phone) => {
        if (typeof phone !== 'string' || phone.length !== 11) {
          return;
        }
        phones.push(phone);
        limits[phone] = DAILY_LIMIT;
      });
    }
    if (raw.limits && typeof raw.limits === 'object') {
      Object.keys(raw.limits).forEach((phone) => {
        if (phone.length === 11) {
          if (!phones.includes(phone)) {
            phones.push(phone);
          }
          limits[phone] = parseInt(String(raw.limits[phone]), 10) || DAILY_LIMIT;
        }
      });
    }
  } catch (_e) {
    console.warn('[server] whitelist.json 未找到或格式错误');
  }
  return { phones, limits };
}

const WHITELIST_CONFIG = loadWhitelistConfig();
const WHITELIST = WHITELIST_CONFIG.phones;
const PHONE_LIMITS = WHITELIST_CONFIG.limits;

const DATA_DIR = path.join(__dirname, 'data');
const SESSIONS_DIR = path.join(DATA_DIR, 'sessions');
const REGION25_INDEX_FILE = path.join(DATA_DIR, 'region25_index.json');
const TOKENS_FILE = path.join(DATA_DIR, 'tokens.json');
const QUOTA_FILE = path.join(DATA_DIR, 'quota.json');
const REGION25_PYTHON_URL = process.env.REGION25_PYTHON_URL || 'http://127.0.0.1:8788';
/** 管理员统计接口密钥；请求头 Authorization: Bearer <key> 或 ?key= */
const ADMIN_STATS_KEY = process.env.ADMIN_STATS_KEY || '';

/** 网页版（qhdhao.cn 等）跨域白名单，逗号分隔；设 * 允许任意来源（仅内测） */
const CORS_ORIGINS = (process.env.CORS_ORIGINS ||
  'http://qhdhao.cn,http://www.qhdhao.cn,https://qhdhao.cn,https://www.qhdhao.cn,http://localhost:8080,http://127.0.0.1:8080')
  .split(',')
  .map((s) => s.trim())
  .filter((s) => s.length > 0);

function applyCors(req, res) {
  const origin = req.headers.origin || '';
  if (CORS_ORIGINS.includes('*')) {
    res.setHeader('Access-Control-Allow-Origin', origin || '*');
  } else if (origin && CORS_ORIGINS.includes(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Vary', 'Origin');
  }
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Max-Age', '86400');
}

if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}
if (!fs.existsSync(SESSIONS_DIR)) {
  fs.mkdirSync(SESSIONS_DIR, { recursive: true });
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_e) {
    return fallback;
  }
}

function writeJson(file, obj) {
  fs.writeFileSync(file, JSON.stringify(obj, null, 2));
}

let tokens = readJson(TOKENS_FILE, {});
let quotaMap = readJson(QUOTA_FILE, {});

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function isWhitelisted(phone) {
  return WHITELIST.includes(phone);
}

function dailyLimitFor(phone) {
  if (!isWhitelisted(phone)) {
    return 0;
  }
  return PHONE_LIMITS[phone] ?? DAILY_LIMIT;
}

function getQuota(phone) {
  const day = todayKey();
  const rec = quotaMap[phone];
  if (!rec || rec.date !== day) {
    return { date: day, used: 0 };
  }
  return rec;
}

function remaining(phone) {
  const limit = dailyLimitFor(phone);
  if (limit <= 0) {
    return 0;
  }
  const q = getQuota(phone);
  return Math.max(0, limit - q.used);
}

function consumeQuota(phone) {
  if (!isWhitelisted(phone)) {
    return { ok: false, message: '不在白名单' };
  }
  const limit = dailyLimitFor(phone);
  const q = getQuota(phone);
  if (q.used >= limit) {
    return { ok: false, message: '今日次数已用完', dailyFreeRemaining: 0, dailyFreeLimit: limit };
  }
  q.used += 1;
  quotaMap[phone] = q;
  writeJson(QUOTA_FILE, quotaMap);
  return { ok: true, dailyFreeRemaining: limit - q.used, dailyFreeLimit: limit };
}

function authPhone(req) {
  const auth = req.headers['authorization'] || '';
  let token = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!token && req.url.includes('?')) {
    const q = req.url.split('?')[1];
    const params = new URLSearchParams(q);
    token = params.get('token') || '';
  }
  const phone = tokens[token];
  if (!phone) {
    return null;
  }
  return { token, phone };
}

/** 管理员统计接口鉴权 */
function authAdmin(req) {
  if (!ADMIN_STATS_KEY || ADMIN_STATS_KEY.length < 8) {
    return false;
  }
  const auth = req.headers['authorization'] || '';
  let key = auth.startsWith('Bearer ') ? auth.slice(7) : '';
  if (!key && req.url.includes('?')) {
    const q = req.url.split('?')[1];
    const params = new URLSearchParams(q);
    key = params.get('key') || params.get('adminKey') || '';
  }
  return key === ADMIN_STATS_KEY;
}

async function dashscopeChat(body) {
  const res = await fetch('https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${DASHSCOPE_KEY}`
    },
    body: JSON.stringify(body)
  });
  const text = await res.text();
  return { status: res.status, body: text };
}

function parseBody(req) {
  return new Promise((resolve) => {
    let data = '';
    req.on('data', (chunk) => { data += chunk; });
    req.on('end', () => {
      try {
        resolve(data.length ? JSON.parse(data) : {});
      } catch (_e) {
        resolve({});
      }
    });
  });
}

function sendJson(res, code, obj) {
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(obj));
}

function readRegion25Index() {
  return readJson(REGION25_INDEX_FILE, {});
}

function writeRegion25Index(index) {
  writeJson(REGION25_INDEX_FILE, index);
}

function appendSessionIndex(phone, sessionId) {
  const index = readRegion25Index();
  if (!Array.isArray(index[phone])) {
    index[phone] = [];
  }
  index[phone].unshift(sessionId);
  index[phone] = index[phone].slice(0, 50);
  writeRegion25Index(index);
}

function sessionBelongsToPhone(sessionId, phone) {
  const metaPath = path.join(SESSIONS_DIR, sessionId, 'meta.json');
  if (!fs.existsSync(metaPath)) {
    return false;
  }
  try {
    const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
    return meta.phone === phone;
  } catch (_e) {
    return false;
  }
}

async function callRegion25Analyze(sessionId, phone, imageBase64, profileGender) {
  const res = await fetch(`${REGION25_PYTHON_URL}/internal/analyze`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sessionId, phone, imageBase64, profileGender: profileGender || '' })
  });
  const text = await res.text();
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch (_e) {
    return { ok: false, status: res.status, message: 'Python 分析服务返回非 JSON', detail: text.slice(0, 200) };
  }
  return { ok: parsed.ok === true, status: res.status, data: parsed, message: parsed.message };
}

function sendFile(res, filePath, contentType) {
  if (!fs.existsSync(filePath)) {
    sendJson(res, 404, { ok: false, message: '文件不存在' });
    return;
  }
  const data = fs.readFileSync(filePath);
  res.writeHead(200, { 'Content-Type': contentType, 'Content-Length': data.length });
  res.end(data);
}

const IMAGE_TYPES = {
  'original.jpg': 'image/jpeg',
  'annotated.jpg': 'image/jpeg',
  'color_report.json': 'application/json; charset=utf-8',
  'regions_pixel.json': 'application/json; charset=utf-8',
  'landmarks_68.json': 'application/json; charset=utf-8',
  'meta.json': 'application/json; charset=utf-8'
};

const server = http.createServer(async (req, res) => {
  applyCors(req, res);
  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  const url = req.url.split('?')[0];

  if (req.method === 'POST' && url === '/v1/auth/register') {
    const body = await parseBody(req);
    const phone = String(body.phone || '').trim();
    if (!/^1[3-9]\d{9}$/.test(phone)) {
      return sendJson(res, 400, { ok: false, message: '手机号格式错误' });
    }
    const token = crypto.randomBytes(24).toString('hex');
    tokens[token] = phone;
    writeJson(TOKENS_FILE, tokens);
    const wl = isWhitelisted(phone);
    return sendJson(res, 200, {
      ok: true,
      token,
      phone,
      isWhitelisted: wl,
      dailyFreeLimit: dailyLimitFor(phone),
      dailyFreeRemaining: remaining(phone)
    });
  }

  if (req.method === 'GET' && url === '/v1/auth/status') {
    const auth = authPhone(req);
    if (!auth) {
      return sendJson(res, 401, { ok: false, message: '未授权' });
    }
    return sendJson(res, 200, {
      ok: true,
      phone: auth.phone,
      isWhitelisted: isWhitelisted(auth.phone),
      dailyFreeLimit: dailyLimitFor(auth.phone),
      dailyFreeRemaining: remaining(auth.phone)
    });
  }

  if (req.method === 'POST' && url === '/v1/quota/consume') {
    const auth = authPhone(req);
    if (!auth) {
      return sendJson(res, 401, { ok: false, message: '未授权' });
    }
    const result = consumeQuota(auth.phone);
    return sendJson(res, result.ok ? 200 : 429, result);
  }

  if (req.method === 'POST' && url === '/v1/vision/analyze') {
    const auth = authPhone(req);
    if (!auth) {
      return sendJson(res, 401, { ok: false, message: '未授权' });
    }
    if (!DASHSCOPE_KEY) {
      return sendJson(res, 500, { ok: false, message: '服务端未配置 DASHSCOPE_API_KEY' });
    }
    const consumed = consumeQuota(auth.phone);
    if (!consumed.ok) {
      return sendJson(res, 429, consumed);
    }

    const body = await parseBody(req);
    const imageUrl = `data:image/jpeg;base64,${body.imageBase64 || ''}`;
    const tagList = '偏白、偏黄、偏红、偏暗沉、偏青白、暗沉、泛红、浮肿、细纹、气色尚可';
    const dsBody = {
      model: 'qwen-vl-plus',
      temperature: 0.2,
      messages: [
        {
          role: 'system',
          content: `你是古籍养生文化自测助手。overallComplexion与matchTags只能从：${tagList}。只输出JSON，不要markdown。字段：overallComplexion,forehead,leftCheek,rightCheek,nose,chin,eyeArea,lipArea,details,confidence,averageBrightness,matchTags`
        },
        {
          role: 'user',
          content: [
            { type: 'text', text: '请按上庭/中庭/五官/下庭分区描述，输出JSON。' },
            { type: 'image_url', image_url: { url: imageUrl } }
          ]
        }
      ]
    };

    const ds = await dashscopeChat(dsBody);
    if (ds.status < 200 || ds.status >= 300) {
      return sendJson(res, 502, { ok: false, message: 'DashScope 调用失败', detail: ds.body.slice(0, 200) });
    }

    let content = '';
    try {
      const parsed = JSON.parse(ds.body);
      content = parsed.choices?.[0]?.message?.content || '';
    } catch (_e) {
      return sendJson(res, 502, { ok: false, message: 'DashScope 返回解析失败' });
    }

    let jsonText = content.trim();
    if (!jsonText.startsWith('{')) {
      const start = jsonText.indexOf('{');
      const end = jsonText.lastIndexOf('}');
      if (start >= 0 && end > start) {
        jsonText = jsonText.slice(start, end + 1);
      }
    }

    let feature;
    try {
      feature = JSON.parse(jsonText);
    } catch (_e) {
      return sendJson(res, 502, { ok: false, message: '模型返回非 JSON' });
    }

    return sendJson(res, 200, {
      ok: true,
      feature,
      dailyFreeRemaining: consumed.dailyFreeRemaining
    });
  }

  if (req.method === 'POST' && url === '/v1/text/generate') {
    const auth = authPhone(req);
    if (!auth) {
      return sendJson(res, 401, { ok: false, message: '未授权' });
    }
    if (!isWhitelisted(auth.phone)) {
      return sendJson(res, 403, { ok: false, message: '不在白名单' });
    }
    if (!DASHSCOPE_KEY) {
      return sendJson(res, 500, { ok: false, message: '服务端未配置 DASHSCOPE_API_KEY' });
    }

    const body = await parseBody(req);
    const dsBody = {
      model: 'qwen-turbo',
      temperature: 0.7,
      messages: [
        { role: 'system', content: body.systemPrompt || '' },
        { role: 'user', content: body.userPrompt || '' }
      ]
    };
    const ds = await dashscopeChat(dsBody);
    if (ds.status < 200 || ds.status >= 300) {
      return sendJson(res, 502, { ok: false, message: 'DashScope 文案失败' });
    }
    let content = '';
    try {
      const parsed = JSON.parse(ds.body);
      content = parsed.choices?.[0]?.message?.content || '';
    } catch (_e) {
      return sendJson(res, 502, { ok: false, message: '文案返回解析失败' });
    }
    return sendJson(res, 200, { ok: true, content });
  }

  // --- 二十五色部云端分析（图片与数据存服务器）---
  if (req.method === 'POST' && url === '/v1/region25/analyze') {
    const auth = authPhone(req);
    if (!auth) {
      return sendJson(res, 401, { ok: false, message: '未授权' });
    }
    const consumed = consumeQuota(auth.phone);
    if (!consumed.ok) {
      return sendJson(res, 429, consumed);
    }

    const body = await parseBody(req);
    const imageBase64 = body.imageBase64 || '';
    const profileGender = String(body.profileGender || '').trim();
    if (!imageBase64) {
      return sendJson(res, 400, { ok: false, message: '缺少 imageBase64' });
    }

    const sessionId = crypto.randomUUID();
    const py = await callRegion25Analyze(sessionId, auth.phone, imageBase64, profileGender);
    if (!py.ok) {
      const code = py.status >= 400 && py.status < 600 ? py.status : 502;
      return sendJson(res, code, { ok: false, message: py.message || '25色部分析失败', detail: py.detail });
    }

    appendSessionIndex(auth.phone, sessionId);

    return sendJson(res, 200, {
      ok: true,
      sessionId,
      colorReport: py.data.colorReport,
      meta: py.data.meta,
      genderCheck: py.data.genderCheck || {},
      urls: {
        report: `/v1/region25/report/${sessionId}`,
        annotatedImage: `/v1/region25/image/${sessionId}/annotated.jpg`,
        originalImage: `/v1/region25/image/${sessionId}/original.jpg`
      },
      dailyFreeRemaining: consumed.dailyFreeRemaining
    });
  }

  if (req.method === 'GET' && url.startsWith('/v1/region25/report/')) {
    const auth = authPhone(req);
    if (!auth) {
      return sendJson(res, 401, { ok: false, message: '未授权' });
    }
    const sessionId = url.replace('/v1/region25/report/', '').split('/')[0];
    if (!sessionId || !sessionBelongsToPhone(sessionId, auth.phone)) {
      return sendJson(res, 404, { ok: false, message: '报告不存在或无权访问' });
    }
    const reportPath = path.join(SESSIONS_DIR, sessionId, 'color_report.json');
    if (!fs.existsSync(reportPath)) {
      return sendJson(res, 404, { ok: false, message: '报告文件不存在' });
    }
    const colorReport = JSON.parse(fs.readFileSync(reportPath, 'utf8'));
    return sendJson(res, 200, {
      ok: true,
      sessionId,
      colorReport,
      urls: {
        annotatedImage: `/v1/region25/image/${sessionId}/annotated.jpg`,
        originalImage: `/v1/region25/image/${sessionId}/original.jpg`
      }
    });
  }

  if (req.method === 'GET' && url.startsWith('/v1/region25/image/')) {
    const auth = authPhone(req);
    if (!auth) {
      return sendJson(res, 401, { ok: false, message: '未授权' });
    }
    const pathOnly = url.split('?')[0];
    const parts = pathOnly.replace('/v1/region25/image/', '').split('/');
    const sessionId = parts[0];
    const fileName = parts.slice(1).join('/') || 'annotated.jpg';
    if (!IMAGE_TYPES[fileName]) {
      return sendJson(res, 400, { ok: false, message: '不支持的文件类型' });
    }
    if (!sessionBelongsToPhone(sessionId, auth.phone)) {
      return sendJson(res, 404, { ok: false, message: '无权访问' });
    }
    return sendFile(res, path.join(SESSIONS_DIR, sessionId, fileName), IMAGE_TYPES[fileName]);
  }

  if (req.method === 'GET' && url.startsWith('/v1/admin/stats')) {
    if (!authAdmin(req)) {
      return sendJson(res, 403, { ok: false, message: '需要管理员密钥（设置 ADMIN_STATS_KEY）' });
    }
    let days = 30;
    if (req.url.includes('?')) {
      const params = new URLSearchParams(req.url.split('?')[1]);
      const d = parseInt(params.get('days') || '30', 10);
      if (d > 0 && d <= 365) {
        days = d;
      }
    }
    const stats = buildUsageStats({ dataDir: DATA_DIR, days, maskPhones: true });
    return sendJson(res, 200, stats);
  }

  if (req.method === 'GET' && url === '/v1/region25/history') {
    const auth = authPhone(req);
    if (!auth) {
      return sendJson(res, 401, { ok: false, message: '未授权' });
    }
    const index = readRegion25Index();
    const ids = Array.isArray(index[auth.phone]) ? index[auth.phone] : [];
    const items = ids.map((sid) => {
      const metaPath = path.join(SESSIONS_DIR, sid, 'meta.json');
      let meta = {};
      if (fs.existsSync(metaPath)) {
        try {
          meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
        } catch (_e) {
          meta = {};
        }
      }
      return {
        sessionId: sid,
        createdAt: meta.createdAt || 0,
        urls: {
          report: `/v1/region25/report/${sid}`,
          annotatedImage: `/v1/region25/image/${sid}/annotated.jpg`
        }
      };
    });
    return sendJson(res, 200, { ok: true, items });
  }

  sendJson(res, 404, { ok: false, message: 'not found' });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Experience server http://0.0.0.0:${PORT}`);
  console.log(`Whitelist: ${WHITELIST.join(', ') || '(empty - set WHITELIST env)'}`);
  WHITELIST.forEach((phone) => {
    console.log(`  ${phone} -> ${dailyLimitFor(phone)} 次/天`);
  });
});
