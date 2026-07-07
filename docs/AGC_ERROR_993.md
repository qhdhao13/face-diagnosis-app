# AGC 上传报错 993（Profile 非法）— 处理清单

**993 = 软件包签名 / Profile 校验失败**，不是包名填错那么简单。  
你当前工程 `build-profile.json5` 里仍是 **`debugKey`（调试证书）**，上传 AGC **必失败**。

---

## 一、必须做的事（按顺序）

### 1. 在 AGC 生成「发布」证书和 Profile

1. 登录 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html)
2. 进入 **用户与访问** → **证书、APP ID 和 Profile**
3. **证书** → 添加 → 类型选 **发布证书**（不是调试）→ 按提示生成并下载 `.p12`、`.cer`
4. **Profile** → 添加 → 类型选 **发布**（内部测试也用发布 Profile，不是 debug）
   - 绑定刚创建的 **发布证书**
   - **包名** 填：`com.face.diagnosis.app`（与 AGC 应用、工程完全一致）
5. 下载 `.p7b` Profile 文件

### 2. 在 DevEco 配置「发布」签名（不要用 debugKey）

1. **File → Project Structure → Signing Configs**
2. 点击 **+** 新建一项，名称例如 **`release`**
3. 填入 AGC 下载的：
   - `.p12` + 密码 + 别名
   - `.cer`
   - `.p7b`（**发布版** Profile）
4. 或：勾选 **Automatically generate signature**，登录华为账号，选中 AGC 里 **`com.face.diagnosis.app`** 的应用，让 DevEco 自动拉 **发布** 配置
5. 打开 **Project → Products → default**：
   - **Build Mode** 选 **release**
   - **Signing Config** 选 **`release`**（不要选带 debugKey 的 default）

### 3. 清理并重新打包

1. **Build → Clean Project**
2. 确认顶部工具栏是 **release**
3. **Build → Build Hap(s)/APP(s) → Build APP(s)**
4. 上传新文件：

```
build/outputs/default/face-diagnosis-app-default-signed.app
```

**不要**再传 `entry/build/.../entry-default-signed.hap`。

### 4. 上传位置

**版本管理 → 软件包管理 → 上传** → 等 **解析成功** → 再去 **内部测试** 选版本。

---

## 二、993 常见原因对照

| 原因 | 你是否中招 |
|------|------------|
| 用了 **debugKey / 调试 Profile** | ✅ 当前工程是 debugKey |
| Profile 包名 ≠ `com.face.diagnosis.app` | 需在 AGC 核对 |
| .p12 / .cer / .p7b 不是同一套 | 重新在 AGC 成套生成 |
| 应用不在 Profile 所属项目下 | 核对 AGC 项目 |
| 上传的是 .hap 不是 .app | 必须用工程级 .app |
| 用 debug 模式打的 release 包 | 顶部须选 release |

---

## 三、在 AGC 看详细报告

软件包列表里点 **993** 或 **查看检测报告**，会写具体哪一项 Profile 校验失败。把那段文字复制下来可进一步排查。

---

## 四、工程侧已调整（2026-07-06）

- `installationFree` 改为 **`false`**：按**可安装应用**走内部测试（免安装元服务另有一套上架流程，易与 993 混淆）

改完后务必 **release + 发布签名** 重新 **Build APP(s)** 再上传。

---

## 五、仍失败时

1. AGC → 该应用 → **应用信息** → 确认包名 `com.face.diagnosis.app`
2. 删除 AGC 里失败的软件包记录，上传**新打的** .app
3. 华为开发者论坛搜「993 Profile」或工单咨询，附上检测报告截图
