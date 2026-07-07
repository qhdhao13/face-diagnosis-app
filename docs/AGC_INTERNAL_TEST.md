# 华为应用市场 · 内部测试分发（给朋友安装，不上架）

> 不上架公开商店，仅通过 **AppGallery Connect 内部测试** 发链接/二维码，朋友用华为账号安装。  
> 包名须与工程一致：`com.face.diagnosis.app`

---

## 应用图标与管理标签（创建应用时）

### 应用图标

AGC 要求：**正方形**；**216×216** 或 **1024×1024**；PNG（≤3 MB）或 WEBP（≤100 KB）；**须与安装包内图标一致**。

已处理：

| 文件 | 用途 |
|------|------|
| `docs/agc/app-icon-1024.png` | **推荐上传 AGC**（1024×1024，约 1.4 MB） |
| `docs/agc/app-icon-216.png` | 备选上传（216×216，约 70 KB） |
| `AppScope/.../app_icon.png` | 工程内应用图标（已与上表 1024 图一致） |
| `entry/.../icon.png` | 入口 Ability 图标（已同步） |

**上传建议**：选 **`app-icon-1024.png`**，与打出来的 `.app` 包内图标一致，最不容易被驳回。

重新打包前若改过图标，须 **Build APP(s) 再打一次包** 再上传。

图标规范：简洁、无医疗红十字误导、无「诊断」「处方」等医疗暗示文字。

### 管理标签 / 应用分类（推荐）

| 项目 | 建议选择 | 避免 |
|------|----------|------|
| **一级分类** | **工具** 或 **生活方式** | 医疗、医院 |
| **二级分类** | 实用工具 / 生活 | 问诊、挂号、医疗诊断 |
| **内容属性** | 文化、养生、娱乐参考 | 医疗服务、诊断治疗 |
| **是否医疗** | **否** | 选「是」会加审核 |
| **涉及个人信息** | **是**（手机号、人脸照片） | — |
| **面向未成年人** | 否（或按实际） | — |

**管理标签**若为多选清单，可勾选与「工具、生活、文化、健康生活方式」相关的；**不要勾**「医疗诊断」「在线问诊」「处方药」等。

一句话说明（若有）：`古籍面诊养生文化自测，上传正脸生成色诊参考报告，非医疗诊断。`

---

## 报错：「没有可供选取的版本」

说明 **还没成功上传软件包**，或 **上传的包解析失败**。按下面顺序做。

### 正确入口（先传包，再选版本）

1. AGC → 你的应用 → **版本管理** → **软件包管理**（或「发布」→「软件包」）
2. 点 **上传**，不要先在「内部测试」里找版本
3. 上传成功后，再回到 **测试 → 内部测试** 里选刚解析出的版本

### 必须上传哪种文件？

| 文件 | 能否上传 |
|------|----------|
| **`build/outputs/default/face-diagnosis-app-default-signed.app`** | ✅ **用这个** |
| `entry-default-signed.hap` | ❌ 单独 HAP 常会解析失败 |
| 微信里发的 `.hap` | ❌ |

本机已有 `.app` 路径（DevEco Build APP 后）：

```
face-diagnosis-app/build/outputs/default/face-diagnosis-app-default-signed.app
```

包内信息应为：`com.face.diagnosis.app` · `1.0.0` · API 12。

### 解析失败最常见原因：仍是调试签名

若 `build-profile.json5` 里 `keyAlias` 仍是 **`debugKey`**，AGC **不接受** 或 **解析失败**。

**必须先改签名再重打 release 包：**

1. DevEco → **File → Project Structure → Signing Configs**
2. 登录华为开发者账号，**关联 AppGallery Connect**
3. 选择应用 `com.face.diagnosis.app`，使用 **发布证书**（不要 debugKey）
4. 顶部构建模式选 **release**
5. **Build → Build Hap(s)/APP(s) → Build APP(s)**
6. 重新上传新的 `face-diagnosis-app-default-signed.app`

### 上传后仍失败时核对

- [ ] AGC 创建应用时包名 = `com.face.diagnosis.app`（一字不差）
- [ ] 上传的是 `.app` 不是 `.hap`
- [ ] release + AGC 发布签名，不是 debug
- [ ] 图标已用 `docs/agc/app-icon-1024.png` 且与工程内图标一致

上传成功时，软件包列表会显示 **1.0.0 (1000000)**，状态为「解析成功」，之后内部测试才能选版本。

---

1. 打开 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)
2. **我的项目** → 新建项目（如 `古籍面诊`）
3. **添加应用** → 选择 **HarmonyOS 应用**
4. 填写：
   - **应用名称**：古籍面诊养生（可改）
   - **应用包名**：`com.face.diagnosis.app`（必须与 `AppScope/app.json5` 完全一致，**创建后不可改**）
   - **应用分类**：工具 / 健康（按实际选，选非医疗说明类即可）

5. 记录 **APP ID**，后续 DevEco 关联要用。

---

## 第二步：配置发布签名（关键）

内部测试 **不能用** 随便发的 debug 包，须用 **AGC 发布证书** 签名。

### 推荐：DevEco 自动签名（最省事）

1. DevEco 打开本项目 `face-diagnosis-app`
2. **File → Project Structure → Project → Signing Configs**
3. 勾选 **Automatically generate signature**（或「关联 AppGallery Connect」）
4. 登录与开发者中心 **同一华为账号**
5. 选择刚创建的应用 `com.face.diagnosis.app`
6. 点击 **Apply** → **OK**  
   DevEco 会在 AGC 生成发布证书并写入 `build-profile.json5`

### 备选：手动在 AGC 生成证书

AGC → 用户与访问 → 证书管理 → 新建发布证书 / Profile → 下载 `.p7b`、`.p12` → 在 Signing Configs 手动填入。

---

## 第三步：打 Release 安装包（.app）

### 方式 A：DevEco 菜单（推荐）

1. 顶部构建模式选 **release**
2. **Build → Build Hap(s)/APP(s) → Build APP(s)**
3. 成功后产物一般在：

```
build/outputs/default/default-default-signed.app
```

或：

```
entry/build/default/outputs/default/entry-default-signed.hap
```

**内部测试请上传 `.app` 包**（整应用）；若控制台只接受 `.app` 而你没有，务必用 **Build APP(s)** 而不是只打 HAP。

### 方式 B：命令行（需本机已装 Java）

```bash
cd face-diagnosis-app
./scripts/build-release-for-agc.sh
```

---

## 第四步：上传到 AGC

1. AGC → 你的应用 → **版本管理** → **软件包管理**
2. **上传** → 选择 `default-default-signed.app`
3. 填写版本说明（如：内部测试 1.0.0，古籍色诊文化自测）
4. 按提示完成：
   - **隐私政策 URL**（必填）：部署 `docs/agc/privacy-policy.html` 后使用  
     `http://qhdhao.cn/sezhen/privacy.html`  
     （本地预览：用浏览器直接打开该 HTML 文件）
   - **隐私政策 · 权限声明**（重要，与包内权限一致）  
     AGC 会校验 **user_grant** 权限是否与隐私政策中勾选的一致。本包仅有一项需用户授权权限：
     | 权限 | HarmonyOS 标识 | 用途（填表时可复制） |
     |------|----------------|----------------------|
     | **相机** | `ohos.permission.CAMERA` | 扫描页拍摄正脸照片用于气色文化自测；可拒绝后改用相册选图 |
     操作：**应用信息 → 隐私声明 / 隐私政策 → 权限说明 → 添加「相机/CAMERA」**，用途与上表一致。  
     若报「只在软件包中的权限：[CAMERA]」，说明控制台未勾选相机，补全后保存再提交版本。
   - **是否涉及个人信息**：是（手机号、人脸照片上传分析）
   - **是否医疗**：否，文化自测 / 养生参考

5. 提交至 **内部测试** 轨道（不要选「正式上架」）

---

## 第五步：添加测试员并分享

1. AGC → **测试** → **内部测试**（或 版本 → 内部测试）
2. **测试用户** → 添加朋友的 **华为 ID 手机号/邮箱**
   - 最多通常 100 人（以控制台为准）
3. 发布该内部测试版本
4. 复制 **邀请链接** 或 **二维码** 发给朋友

朋友操作：

1. 在鸿蒙手机浏览器打开链接，或应用市场搜索内部测试邀请
2. 使用 **已被添加的华为账号** 登录
3. 安装「古籍面诊养生」

---

## 第六步：体验服白名单（别忘）

App 走体验模式时，朋友还要在服务器白名单里：

```bash
# 服务器 /opt/face-diagnosis/experience-server/whitelist.json
# 或环境变量 WHITELIST=朋友手机号
systemctl restart face-experience
```

网页版仍可用：http://qhdhao.cn/sezhen/

---

## 常见问题

### 本地构建报错 00303074（bundleName 不匹配）？

说明 `build-profile.json5` 里 Profile 选错了（常见：误用 `zuwa_clock` 的 `.p7b`）。  
**按 `docs/SIGNING_FIX.md` 修复**，不要在本工程 Signing Configs 里选其他应用的证书。

### 朋友打不开 HAP 文件？

正常。HAP 不能微信直装。必须走 **内部测试链接** 或 **hdc 线刷**。

### 提示「无法安装」「签名不一致」？

- 包名与 AGC 应用不一致
- 用了 debug 包而非 release 发布签名包
- 测试员华为账号未加入内部测试名单

### 朋友是苹果 / 安卓？

装不了鸿蒙 App，请发 **网页版** 链接。

### 和「上架」有什么区别？

| | 内部测试 | 正式上架 |
|--|----------|----------|
| 谁可见 | 仅邀请的测试员 | 全市场用户 |
| 审核 | 相对宽松 | 严格 |
| 链接 | 专用测试链接 | 应用市场搜索 |

---

## 本项目固定信息（填表用）

| 字段 | 值 |
|------|-----|
| 包名 | `com.face.diagnosis.app` |
| 版本名 | `1.0.0` |
| 版本号 | `1000000` |
| 供应商 | `qhdhao` |
| 展示名 | 古籍面诊养生 |
| 网络 | 需联网访问体验服 `49.232.232.27:8787` |
| 权限 | 相机（ohos.permission.CAMERA）、网络、网络状态 |
| 隐私政策 URL | `http://qhdhao.cn/sezhen/privacy.html`（源文件 `docs/agc/privacy-policy.html`） |

---

## 发给朋友的一段话（可复制）

```
古籍面诊色诊 · 内部测试邀请（文化自测娱乐，非医疗）

1. 你需要华为手机 + HarmonyOS NEXT
2. 用我添加过的华为账号，打开这个链接安装：【AGC 内部测试链接】
3. 打开 App → 设置里注册手机号（我帮你加白名单）
4. 扫描页可拍照或上传相册正脸图

装不了的话，用浏览器：http://qhdhao.cn/sezhen/
```

---

完成 AGC 创建应用并打好 `.app` 后，若某一步报错，把 **截图或报错原文** 发我，可继续帮你对。
