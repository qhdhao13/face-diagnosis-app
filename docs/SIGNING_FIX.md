# 签名配置修复：00303074 bundleName 不匹配

## 错误现象

```
hvigor ERROR: 00303074 Configuration Error
The bundleName in app.json5 does not match the bundleName in the generated SigningConfigs.
```

## 原因

`AppScope/app.json5` 包名是 **`com.face.diagnosis.app`**，但 `build-profile.json5` 里 Profile（`.p7b`）来自别的应用（例如 **`com.zuwa.clock`** 的 `zuwa_clock_release_profileRelease.p7b`）。

**三件套必须同一应用、同一套证书：**

| 文件 | 本工程正确值 |
|------|----------------|
| storeFile (.p12) | `default_face-diagnosis-app_....p12` |
| certpath (.cer) | 同上前缀的 `.cer` |
| profile (.p7b) | 同上前缀的 `.p7b`，内含 `bundle-name: com.face.diagnosis.app` |

## 发布签名（AGC 上传）当前配置

`build-profile.json5` 已配置为：

| 项 | 值 |
|----|-----|
| keyAlias | **`releasekey`**（不是 `debugKey`） |
| storeFile | `face-diagnosis-release.p12` |
| certpath | `face-diagnosis-release-cert.cer`（须含 **3 段证书链**：根 + 中间 + 叶） |
| profile | `face-diagnosis-release-profileRelease.p7b` |

若报 **11013004 Profile cert must a cert chain**，说明 `.cer` 只有一张证书。应从 AGC 重新下载完整发布证书，或确保 `face-diagnosis-release-cert.cer` 含根、中间、叶三段。

本地 **release** 构建成功产物：

```
build/outputs/default/face-diagnosis-app-default-signed.app
```

---

## 已修复（本地调试打包）

`build-profile.json5` 调试时可改回 DevEco 自动生成的 **default 调试三件套**（路径在 `~/.ohos/config/default_face-diagnosis-app_*`）。

错误的 `zuwa_clock` Profile 已移到：

```
docs/agc/WRONG-zuwa_clock-do-not-use.p7b
```

**请勿再选这个文件。**

## DevEco 里不要再点错

在 **File → Project Structure → Signing Configs** 里：

1. **不要** 选 `zuwa_clock` 或任何包名不是 `com.face.diagnosis.app` 的 Profile
2. 若点 **Apply** 后构建又失败，说明 DevEco 写坏了 `build-profile.json5`
3. 用 Git 恢复：  
   `git checkout build-profile.json5`  
   或对照本文「已修复」一节的路径手动改回

## 本地 Debug 构建

1. 构建模式选 **debug**
2. **Build → Build Hap(s)/APP(s)**（或 Build APP(s)）
3. 应不再出现 00303074

## 上传 AGC 内部测试（Release）

Debug 包 **不能** 上传 AGC。需要：

1. AGC → 证书管理 → 为 **`com.face.diagnosis.app`** 申请 **发布 Profile（.p7b）**
2. 绑定已有 **`face-diagnosis-release-cert.cer`**（不要用 zuwa 的证书）
3. DevEco 新建 **release** 签名项：  
   - `face-diagnosis-release.p12`  
   - `face-diagnosis-release-cert.cer`  
   - 新下载的 **face-diagnosis-release.p7b**（包名必须是 `com.face.diagnosis.app`）
4. 构建模式 **release** → **Build APP(s)**
5. 上传 `build/outputs/default/face-diagnosis-app-default-signed.app`

详见 `docs/AGC_ERROR_993.md`。

---

## 报错 11014003：keystore password was incorrect

说明 `build-profile.json5` 里保存的 **加密密码** 与 `face-diagnosis-release.p12` **实际密码不一致**（常见于手动改过 .p12，或 DevEco 里输错密码后点了 Apply）。

### 处理步骤

1. 回忆创建 `.p12` 时设的**明文密码**（在 AGC 下载或本地 openssl 生成时设置）
2. 终端验证（可选）：
   ```bash
   cd face-diagnosis-app
   chmod +x scripts/verify-release-p12.sh
   ./scripts/verify-release-p12.sh
   ```
3. DevEco → **File → Project Structure → Signing Configs**
4. 选中 **default**（或你的 release 配置）
5. **重新输入** Store Password、Key Password（明文，与创建 p12 时一致）
6. 核对 **keyAlias** 与 `verify-release-p12.sh` 输出里的别名一致（不一定是 `debugKey`）
7. **Apply → OK**
8. 构建模式 **release** → **Build APP(s)**

### 若忘记 .p12 密码

无法找回，只能：

1. AGC 作废旧发布证书，重新申请发布证书 + Profile
2. 用新密码生成新 `.p12`
3. 在 DevEco 重新配置三件套

或改用 DevEco **自动签名**（关联 AGC 应用），由 IDE 生成并保存正确密码。

