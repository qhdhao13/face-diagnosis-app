/**
 * 网页版色诊 API 配置
 * qhdhao.cn 上走同域反代 /face-api，避免跨域
 */
(function () {
  const host = typeof location !== 'undefined' ? location.hostname : '';
  if (host === 'qhdhao.cn' || host === 'www.qhdhao.cn') {
    window.FACE_API_BASE = '/face-api';
  } else if (!window.FACE_API_BASE) {
    window.FACE_API_BASE = 'http://49.232.232.27:8787';
  }
})();
