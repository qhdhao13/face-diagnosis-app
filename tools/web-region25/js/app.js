/**
 * 二十五明堂色诊 · 网页版
 */
(function () {
  const STORAGE_TOKEN = 'face_region25_token';
  const STORAGE_PHONE = 'face_region25_phone';

  const $ = (id) => document.getElementById(id);
  const apiBase = () => (window.FACE_API_BASE || '').replace(/\/$/, '');

  function authHeaders() {
    const token = localStorage.getItem(STORAGE_TOKEN) || '';
    return {
      'Content-Type': 'application/json',
      Authorization: token ? `Bearer ${token}` : '',
    };
  }

  function setStatus(msg, isError) {
    const el = $('status');
    el.textContent = msg;
    el.className = isError ? 'status error' : 'status';
  }

  function showResult(show) {
    $('result').hidden = !show;
  }

  async function apiPost(path, body) {
    const res = await fetch(`${apiBase()}${path}`, {
      method: 'POST',
      headers: authHeaders(),
      body: JSON.stringify(body),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.message || `HTTP ${res.status}`);
    return data;
  }

  async function apiGet(path) {
    const res = await fetch(`${apiBase()}${path}`, { headers: authHeaders() });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(data.message || `HTTP ${res.status}`);
    return data;
  }

  function fileToBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        const s = reader.result;
        const idx = String(s).indexOf(',');
        resolve(idx >= 0 ? String(s).slice(idx + 1) : String(s));
      };
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  }

  function loadPreview(file) {
    const url = URL.createObjectURL(file);
    $('preview').src = url;
    $('preview').hidden = false;
    $('photoName').textContent = `已选：${file.name || '照片'}`;
  }

  function clearPhotoSelection() {
    $('photo').value = '';
    $('preview').hidden = true;
    $('preview').removeAttribute('src');
    $('photoName').textContent = '未选择照片';
  }

  async function refreshQuota() {
    try {
      const data = await apiGet('/v1/auth/status');
      $('quota').textContent = data.isWhitelisted
        ? `白名单用户 · 今日剩余 ${data.dailyFreeRemaining}/${data.dailyFreeLimit} 次`
        : '未在白名单，无法使用云端分析（请联系管理员）';
    } catch (_e) {
      $('quota').textContent = '未登录';
    }
  }

  async function registerPhone() {
    const phone = $('phone').value.trim();
    if (!/^1[3-9]\d{9}$/.test(phone)) {
      setStatus('请输入 11 位有效手机号', true);
      return;
    }
    setStatus('正在注册…');
    try {
      const data = await apiPost('/v1/auth/register', { phone });
      localStorage.setItem(STORAGE_TOKEN, data.token);
      localStorage.setItem(STORAGE_PHONE, data.phone);
      $('phoneDisplay').textContent = data.phone;
      setStatus(data.isWhitelisted ? '注册成功，已在白名单' : '已注册，但不在白名单');
      await refreshQuota();
    } catch (err) {
      setStatus(err.message || '注册失败', true);
    }
  }

  async function analyze() {
    const fileInput = $('photo');
    const file = fileInput.files && fileInput.files[0];
    const token = localStorage.getItem(STORAGE_TOKEN);
    if (!token) {
      setStatus('请先注册手机号', true);
      return;
    }
    if (!file) {
      setStatus('请先点击「上传已有照片」选择一张正脸人像', true);
      return;
    }

    $('analyzeBtn').disabled = true;
    setStatus('正在上传并分析（约 10～30 秒）…');
    showResult(false);

    try {
      const imageBase64 = await fileToBase64(file);
      const profileGender = $('gender').value;
      const data = await apiPost('/v1/region25/analyze', {
        imageBase64,
        width: 0,
        height: 0,
        profileGender: profileGender === '未设置' ? '' : profileGender,
      });

      if (data.genderCheck && data.genderCheck.mismatch) {
        throw new Error(data.genderCheck.warning || '性别与设置不符');
      }

      const report = data.colorReport;
      const tokenQ = encodeURIComponent(token);
      const annUrl = `${apiBase()}${data.urls.annotatedImage}?token=${tokenQ}`;

      $('annotated').src = annUrl;
      $('sessionId').textContent = data.sessionId;
      $('summary').textContent = buildClassicalSummary(report);

      const list = $('lineItems');
      list.innerHTML = '';
      (report.line_items || []).forEach((line, i) => {
        const li = document.createElement('li');
        li.textContent = `${i + 1}. ${line}`;
        list.appendChild(li);
      });

      $('engine').textContent = 'region25_cloud（网页版）';
      if (data.dailyFreeRemaining !== undefined) {
        $('quota').textContent = `今日剩余 ${data.dailyFreeRemaining} 次`;
      }
      showResult(true);
      setStatus('分析完成');
    } catch (err) {
      setStatus(err.message || '分析失败', true);
    } finally {
      $('analyzeBtn').disabled = false;
    }
  }

  function init() {
    const savedPhone = localStorage.getItem(STORAGE_PHONE);
    if (savedPhone) {
      $('phone').value = savedPhone;
      $('phoneDisplay').textContent = savedPhone;
      refreshQuota();
    }

    $('registerBtn').addEventListener('click', registerPhone);
    $('pickPhotoBtn').addEventListener('click', () => {
      $('photo').click();
    });
    $('photo').addEventListener('change', (e) => {
      const f = e.target.files && e.target.files[0];
      if (f) {
        loadPreview(f);
        setStatus('照片已选，可点击「开始色诊分析」');
      } else {
        clearPhotoSelection();
      }
    });
    $('analyzeBtn').addEventListener('click', analyze);
  }

  document.addEventListener('DOMContentLoaded', init);
})();
