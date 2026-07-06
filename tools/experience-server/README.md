# 体验免 Key 代理服务

DashScope Key **只放在本服务的环境变量**，App 内不包含 Key。

## 安装并启动

```bash
cd tools/experience-server
npm install
export DASHSCOPE_API_KEY=你的通义Key
export WHITELIST=13800138000,13900139000
npm start
```

## 修改 App 服务端地址

编辑 `AppConstants.ets` 中 `ExperienceServerConfig.BASE_URL`，真机用电脑局域网 IP。

## 白名单管理

环境变量 `WHITELIST` 逗号分隔 11 位手机号，改后重启服务。
