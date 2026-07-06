# 网页版二十五明堂色诊 · 部署到 qhdhao.cn

源码目录：`tools/web-region25/`

## 一、体验服开启跨域（必做）

网页在 `qhdhao.cn` 域名下，需调用 `49.232.232.27:8787` 的 API。已在 `experience-server/server.js` 加入 CORS，默认允许：

- `http://qhdhao.cn` / `http://www.qhdhao.cn`
- `https://qhdhao.cn`（若日后上 HTTPS）

**在腾讯云体验服上重启 Node：**

```bash
cd /opt/face-diagnosis/experience-server   # 按你实际路径
git pull   # 或 rsync 同步 server.js
sudo systemctl restart face-experience
```

可选环境变量：

```bash
CORS_ORIGINS=http://qhdhao.cn,https://qhdhao.cn npm start
```

## 二、把静态页放到 qhdhao.cn

### 方式 A：子目录（推荐）

1. 将 `tools/web-region25/` 整个目录上传到服务器，例如：

   `/var/www/qhdhao/sezhen/`

2. Nginx 增加（在 qhdhao.cn 的 server 块内）：

```nginx
location /sezhen/ {
    alias /var/www/qhdhao/sezhen/;
    index index.html;
    try_files $uri $uri/ /sezhen/index.html;
}
```

3. 访问地址：**http://qhdhao.cn/sezhen/**

### 方式 B：同域反代 API（避免浏览器跨域）

若希望 API 也走 `qhdhao.cn`，可在 Nginx 增加：

```nginx
location /face-api/ {
    proxy_pass http://49.232.232.27:8787/;
    proxy_set_header Host $host;
    proxy_read_timeout 120s;
    client_max_body_size 20m;
}
```

并修改 `sezhen/config.js`：

```javascript
window.FACE_API_BASE = '/face-api';
```

## 三、在明史检索首页加链接

编辑 qhdhao.cn 的 `index.html`（或模板），在标题附近加入：

```html
<p style="margin:12px 0;text-align:center;">
  <a href="/sezhen/" style="color:#8b4513;font-weight:bold;">
    二十五明堂色诊（网页版 · 古籍养生自测）
  </a>
</p>
```

也可使用本目录下的 `qhdhao-nav-snippet.html` 复制粘贴。

## 四、使用说明

1. 打开 http://qhdhao.cn/sezhen/
2. 输入已在白名单的手机号（与 App 相同，如 18903351102）→ 注册
3. 可选填性别 → 上传/拍摄正脸照 → **开始色诊分析**
4. 查看标注图、综合（古籍体例）、25 区分项

## 五、注意事项

| 项目 | 说明 |
|------|------|
| 配额 | 与白名单 App 共用每日次数 |
| HTTPS | 若全站 HTTPS 而 API 仍为 HTTP，浏览器会拦截；请用方式 B 反代或给体验服配 HTTPS |
| 隐私 | 照片存于体验服 `data/sessions/`，仅供自测 |

## 六、本地预览

```bash
cd tools/web-region25
python3 -m http.server 8080
# 浏览器打开 http://127.0.0.1:8080
# 需在体验服 CORS 中包含 http://127.0.0.1:8080（已默认包含）
```
