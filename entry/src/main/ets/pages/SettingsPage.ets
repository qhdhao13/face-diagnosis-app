/**
 * 模块8：独立设置配置页
 * 四大子板块：基础信息 / 模型配置 / 版本更新 / 开发者信息
 */
import { NavigationHelper } from '../common/utils/NavigationHelper';
import { AppState } from '../common/AppBootstrap';
import { ModuleRegistry } from '../common/ModuleRegistry';
import {
  ModelType, ModelUsageMode, NetworkAuthLevel, UserProfile, ModelConfig, VersionInfo
} from '../common/types/AppTypes';
import { DefaultModelConfig, ComplianceTexts, AppVersion, MemberConfig, ExperienceServerConfig } from '../common/constants/AppConstants';
import { NetworkAuthDialog } from '../components/NetworkAuthDialog';

@Entry
@Component
struct SettingsPage {
  private uiContext: UIContext = this.getUIContext();
  @State nickname: string = '';
  @State gender: string = '未设置';
  @State age: number = 0;
  @State modelType: ModelType = ModelType.OFFICIAL;
  @State privateToken: string = '';
  @State apiEndpoint: string = '';
  @State apiKey: string = '';
  @State visionModelName: string = '';
  @State usageMode: ModelUsageMode = ModelUsageMode.EXPERIENCE;
  @State phoneNumber: string = '';
  @State isPhoneRegistered: boolean = false;
  @State isPhoneWhitelisted: boolean = false;
  @State dailyFreeRemaining: number = 0;
  @State memberId: string = '';
  @State isMemberApproved: boolean = false;
  @State versionInfo: VersionInfo = {
    currentVersion: AppVersion.CURRENT, latestVersion: AppVersion.CURRENT,
    updateLog: '', hasUpdate: false
  };
  @State showModelTip: boolean = true;
  @State statusMessage: string = '';

  networkDialogController: CustomDialogController = new CustomDialogController({
    builder: NetworkAuthDialog({
      onSelect: (level: NetworkAuthLevel) => {
        this.handleNetworkAuth(level);
      }
    }),
    autoCancel: true,
    alignment: DialogAlignment.Center
  });

  async aboutToAppear(): Promise<void> {
    await this.loadSettings();
  }

  /** 加载全部设置项 */
  async loadSettings(): Promise<void> {
    if (AppState.settingsModule !== null) {
      const profile = await AppState.settingsModule.getUserProfile();
      this.nickname = profile.nickname;
      this.gender = profile.gender;
      this.age = profile.age;
    }

    const modelConfig = ModuleRegistry.getModelConfig();
    const config = modelConfig.getConfig();
    this.modelType = config.modelType;
    this.privateToken = config.privateToken;
    this.apiEndpoint = config.apiEndpoint;
    this.apiKey = config.apiKey;
    this.visionModelName = config.visionModelName.length > 0
      ? config.visionModelName
      : DefaultModelConfig.OFFICIAL_VISION_MODEL_NAME;
    this.usageMode = config.usageMode ?? ModelUsageMode.EXPERIENCE;

    const phoneAuth = ModuleRegistry.getPhoneAuth();
    const phoneStatus = phoneAuth.getStatus();
    this.phoneNumber = phoneStatus.phoneNumber;
    this.isPhoneRegistered = phoneAuth.isPhoneRegistered();
    this.isPhoneWhitelisted = phoneStatus.isWhitelisted;
    this.dailyFreeRemaining = phoneStatus.dailyFreeRemaining;
    if (this.isPhoneRegistered) {
      await phoneAuth.refreshStatus();
      const refreshed = phoneAuth.getStatus();
      this.isPhoneWhitelisted = refreshed.isWhitelisted;
      this.dailyFreeRemaining = refreshed.dailyFreeRemaining;
    }

    const memberAuth = ModuleRegistry.getMemberAuth();
    const status = memberAuth.getStatus();
    this.memberId = status.memberId;
    this.isMemberApproved = status.isRegistered && status.isApproved;
    // 已注册但未审批时，尝试按 VIP_ 规则刷新（方案 A）
    if (status.isRegistered && !status.isApproved) {
      this.isMemberApproved = await memberAuth.refreshApproval();
    }

    if (AppState.settingsModule !== null) {
      this.versionInfo = AppState.settingsModule.versionUpdate.getCurrentVersionInfo();
    }
  }

  /** 保存用户基础信息 */
  async saveProfile(): Promise<void> {
    if (AppState.settingsModule === null) return;
    const profile: UserProfile = {
      nickname: this.nickname,
      gender: this.gender,
      age: this.age
    };
    await AppState.settingsModule.saveUserProfile(profile);
    this.statusMessage = '基础信息已保存（仅本地）';
  }

  /** 保存模型配置 */
  async saveModelConfig(): Promise<void> {
    try {
      const phoneAuth = ModuleRegistry.getPhoneAuth();
      if (!phoneAuth.isPhoneRegistered()) {
        this.statusMessage = '请先注册手机号后再保存模型配置';
        return;
      }

      const modelConfig = ModuleRegistry.getModelConfig();
      const config: ModelConfig = {
        modelType: this.modelType,
        apiEndpoint: this.apiEndpoint.length > 0 ? this.apiEndpoint : DefaultModelConfig.OFFICIAL_ENDPOINT,
        apiPort: 443,
        apiKey: this.apiKey,
        visionModelName: this.visionModelName.length > 0
          ? this.visionModelName
          : DefaultModelConfig.OFFICIAL_VISION_MODEL_NAME,
        privateToken: this.privateToken,
        isOfficialRecommended: this.modelType === ModelType.OFFICIAL,
        usageMode: this.usageMode
      };
      await modelConfig.saveConfig(config);
      this.statusMessage = '模型配置已保存';
    } catch (err) {
      this.statusMessage = `${err}`;
    }
  }

  /** 注册手机号 */
  async registerPhone(): Promise<void> {
    const phoneAuth = ModuleRegistry.getPhoneAuth();
    const success = await phoneAuth.registerPhone(this.phoneNumber);
    if (success) {
      const status = phoneAuth.getStatus();
      this.isPhoneRegistered = true;
      this.isPhoneWhitelisted = status.isWhitelisted;
      this.dailyFreeRemaining = status.dailyFreeRemaining;
      this.statusMessage = status.isWhitelisted
        ? `手机号已注册，白名单通过，今日剩余 ${status.dailyFreeRemaining} 次`
        : '手机号已注册，尚未加入白名单，体验免 Key 不可用，可切换自带 Key';
    } else {
      this.statusMessage = '注册失败：请检查 11 位手机号及服务端地址是否可访问';
    }
  }

  async refreshPhoneStatus(): Promise<void> {
    const phoneAuth = ModuleRegistry.getPhoneAuth();
    if (!phoneAuth.isPhoneRegistered()) {
      this.statusMessage = '请先注册手机号';
      return;
    }
    await phoneAuth.refreshStatus();
    const status = phoneAuth.getStatus();
    this.isPhoneWhitelisted = status.isWhitelisted;
    this.dailyFreeRemaining = status.dailyFreeRemaining;
    this.statusMessage = `今日剩余免费 ${status.dailyFreeRemaining}/${status.dailyFreeLimit} 次`;
  }

  /** 注册会员 */
  async registerMember(): Promise<void> {
    const memberAuth = ModuleRegistry.getMemberAuth();
    const success = await memberAuth.registerMember(this.memberId);
    if (success) {
      this.isMemberApproved = await memberAuth.checkApproval();
      this.statusMessage = this.isMemberApproved
        ? `会员 ${this.memberId} 已审批，可使用私有模型`
        : '注册成功，但 ID 非 VIP_ 前缀，当前内测仅支持 VIP_ 账号';
    } else {
      this.statusMessage = `会员 ID 至少 ${MemberConfig.MIN_ID_LENGTH} 位`;
    }
  }

  /** 刷新 VIP_ 审批状态 */
  async refreshMemberApproval(): Promise<void> {
    const memberAuth = ModuleRegistry.getMemberAuth();
    this.isMemberApproved = await memberAuth.refreshApproval();
    const status = memberAuth.getStatus();
    this.memberId = status.memberId;
    if (!status.isRegistered) {
      this.statusMessage = '尚未注册会员';
      return;
    }
    if (this.isMemberApproved) {
      this.statusMessage = `会员 ${status.memberId} 已通过内测审批`;
    } else {
      this.statusMessage = '未通过：请使用开发者发放的 VIP_ 开头会员 ID';
    }
  }

  /** 处理联网授权选择 */
  async handleNetworkAuth(level: NetworkAuthLevel): Promise<void> {
    if (AppState.networkAuthModule !== null) {
      // 用户同意联网时，同步申请系统网络权限
      if (level !== NetworkAuthLevel.DENY) {
        const permission = ModuleRegistry.getPermission();
        const result = await permission.requestNetworkPermission();
        if (!result.granted) {
          this.statusMessage = '网络权限未授予，联网功能不可用';
          await AppState.networkAuthModule.saveAuthLevel(NetworkAuthLevel.DENY);
          return;
        }
      }

      await AppState.networkAuthModule.saveAuthLevel(level);
      if (level !== NetworkAuthLevel.DENY && AppState.settingsModule !== null) {
        this.versionInfo = await AppState.settingsModule.versionUpdate.checkForUpdate();
        this.statusMessage = this.versionInfo.hasUpdate
          ? `发现新版本 ${this.versionInfo.latestVersion}`
          : '已联网，当前为最新版本';
      }
    }
  }

  /** 重置模型为默认 */
  async resetModel(): Promise<void> {
    const modelConfig = ModuleRegistry.getModelConfig();
    await modelConfig.resetToDefault();
    this.modelType = ModelType.OFFICIAL;
    this.privateToken = '';
    this.apiEndpoint = DefaultModelConfig.OFFICIAL_ENDPOINT;
    this.apiKey = '';
    this.visionModelName = DefaultModelConfig.OFFICIAL_VISION_MODEL_NAME;
    this.usageMode = ModelUsageMode.EXPERIENCE;
    this.statusMessage = '已恢复默认配置';
  }

  build() {
    Column() {
      Row() {
        Text('←')
          .fontSize(22)
          .fontColor($r('app.color.primary'))
          .onClick(() => NavigationHelper.back(this.uiContext))
        Text('设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank().width(22)
      }
      .width('100%')
      .padding(16)

      Scroll() {
        Column() {
          // === 子板块1：面诊基础信息 ===
          this.SectionTitle('面诊基础信息')
          TextInput({ placeholder: '昵称/姓名', text: this.nickname })
            .onChange((v: string) => { this.nickname = v; })
            .margin({ bottom: 8 })
          Row() {
            Text('性别：').fontSize(14)
            Button(this.gender === '男' ? '✓ 男' : '男')
              .fontSize(13).height(32)
              .backgroundColor(this.gender === '男' ? $r('app.color.primary') : $r('app.color.divider'))
              .onClick(() => { this.gender = '男'; })
            Button(this.gender === '女' ? '✓ 女' : '女')
              .fontSize(13).height(32).margin({ left: 8 })
              .backgroundColor(this.gender === '女' ? $r('app.color.primary') : $r('app.color.divider'))
              .onClick(() => { this.gender = '女'; })
          }.margin({ bottom: 8 })
          TextInput({ placeholder: '年龄', text: this.age > 0 ? `${this.age}` : '' })
            .type(InputType.Number)
            .onChange((v: string) => { this.age = parseInt(v) || 0; })
            .margin({ bottom: 8 })
          Button('保存基础信息')
            .width('100%').height(40).fontSize(14)
            .backgroundColor($r('app.color.primary'))
            .onClick(() => this.saveProfile())

          // === 子板块2：手机号与模型 ===
          this.SectionTitle('手机号注册（必填）')
          Text(ExperienceServerConfig.PHONE_HINT)
            .fontSize(12).fontColor($r('app.color.warning')).lineHeight(18).margin({ bottom: 8 })
          TextInput({ placeholder: '11 位手机号', text: this.phoneNumber })
            .type(InputType.PhoneNumber)
            .onChange((v: string) => { this.phoneNumber = v; }).margin({ bottom: 8 })
          Row() {
            Button('注册手机号').layoutWeight(1).height(36).fontSize(13)
              .backgroundColor($r('app.color.primary_light'))
              .onClick(() => this.registerPhone())
            Button('刷新配额').layoutWeight(1).height(36).fontSize(13).margin({ left: 8 })
              .backgroundColor($r('app.color.divider'))
              .onClick(() => this.refreshPhoneStatus())
          }.margin({ bottom: 8 })
          if (this.isPhoneRegistered) {
            Text(this.isPhoneWhitelisted
              ? `✓ 白名单已通过，今日免费剩余 ${this.dailyFreeRemaining} 次`
              : '已注册，未在白名单（体验免 Key 不可用）')
              .fontSize(12)
              .fontColor(this.isPhoneWhitelisted ? $r('app.color.success') : $r('app.color.warning'))
              .margin({ bottom: 12 })
          }

          this.SectionTitle('模型与API配置')
          if (this.showModelTip) {
            Text(DefaultModelConfig.OFFICIAL_TIP)
              .fontSize(12).fontColor($r('app.color.accent'))
              .padding(8).backgroundColor('#FFF8E7').borderRadius(8)
              .margin({ bottom: 8 })
          }

          Row() {
            Button(this.usageMode === ModelUsageMode.EXPERIENCE ? '✓ 体验免Key' : '体验免Key')
              .fontSize(13).height(36).layoutWeight(1)
              .backgroundColor(this.usageMode === ModelUsageMode.EXPERIENCE ? $r('app.color.primary') : $r('app.color.divider'))
              .onClick(() => { this.usageMode = ModelUsageMode.EXPERIENCE; this.modelType = ModelType.OFFICIAL; })
            Button(this.usageMode === ModelUsageMode.BYOK ? '✓ 自带Key' : '自带Key')
              .fontSize(13).height(36).layoutWeight(1).margin({ left: 8 })
              .backgroundColor(this.usageMode === ModelUsageMode.BYOK ? $r('app.color.primary') : $r('app.color.divider'))
              .onClick(() => { this.usageMode = ModelUsageMode.BYOK; })
          }.margin({ bottom: 8 })

          Row() {
            Button(this.modelType === ModelType.OFFICIAL ? '✓ 官方推荐' : '官方推荐')
              .fontSize(13).height(36).layoutWeight(1)
              .backgroundColor(this.modelType === ModelType.OFFICIAL ? $r('app.color.primary') : $r('app.color.divider'))
              .onClick(() => { this.modelType = ModelType.OFFICIAL; })
            Button(this.modelType === ModelType.PRIVATE ? '✓ 私有模型' : '私有模型')
              .fontSize(13).height(36).layoutWeight(1).margin({ left: 8 })
              .backgroundColor(this.modelType === ModelType.PRIVATE ? $r('app.color.primary') : $r('app.color.divider'))
              .enabled(this.isMemberApproved)
              .opacity(this.isMemberApproved ? 1 : 0.5)
              .onClick(() => { this.modelType = ModelType.PRIVATE; })
          }.margin({ bottom: 8 })

          if (!this.isMemberApproved) {
            Text(MemberConfig.VIP_TEST_HINT)
              .fontSize(12).fontColor($r('app.color.warning')).lineHeight(18).margin({ bottom: 8 })
            TextInput({
              placeholder: `输入会员 ID（须 ${MemberConfig.VIP_PREFIX} 开头，如 ${MemberConfig.VIP_PREFIX}张三）`,
              text: this.memberId
            })
              .onChange((v: string) => { this.memberId = v; }).margin({ bottom: 8 })
            Row() {
              Button('注册会员').layoutWeight(1).height(36).fontSize(13)
                .backgroundColor($r('app.color.primary_light'))
                .onClick(() => this.registerMember())
              Button('刷新状态').layoutWeight(1).height(36).fontSize(13).margin({ left: 8 })
                .backgroundColor($r('app.color.divider'))
                .onClick(() => this.refreshMemberApproval())
            }.margin({ bottom: 8 })
          } else {
            Text(`✓ 内测会员已审批：${this.memberId}`)
              .fontSize(12).fontColor($r('app.color.success')).margin({ bottom: 8 })
          }

          TextInput({ placeholder: 'API 地址（可填 .../v1 或 .../chat/completions）', text: this.apiEndpoint })
            .onChange((v: string) => { this.apiEndpoint = v; }).margin({ bottom: 8 })
            .visibility(this.usageMode === ModelUsageMode.BYOK ? Visibility.Visible : Visibility.None)
          TextInput({ placeholder: 'API Key（通义 DashScope）', text: this.apiKey })
            .type(InputType.Password)
            .onChange((v: string) => { this.apiKey = v; }).margin({ bottom: 8 })
            .visibility(this.usageMode === ModelUsageMode.BYOK ? Visibility.Visible : Visibility.None)
          TextInput({
            placeholder: `视觉模型（默认 ${DefaultModelConfig.OFFICIAL_VISION_MODEL_NAME}）`,
            text: this.visionModelName
          })
            .onChange((v: string) => { this.visionModelName = v; }).margin({ bottom: 8 })
            .visibility(this.usageMode === ModelUsageMode.BYOK ? Visibility.Visible : Visibility.None)
          TextInput({ placeholder: '私有模型 Token', text: this.privateToken })
            .onChange((v: string) => { this.privateToken = v; }).margin({ bottom: 8 })
          Row() {
            Button('保存配置').layoutWeight(1).height(36).fontSize(13)
              .backgroundColor($r('app.color.primary'))
              .onClick(() => this.saveModelConfig())
            Button('恢复默认').layoutWeight(1).height(36).fontSize(13).margin({ left: 8 })
              .backgroundColor($r('app.color.divider'))
              .onClick(() => this.resetModel())
          }.margin({ bottom: 8 })

          // === 子板块3：版本更新 ===
          this.SectionTitle('版本更新')
          Text(`当前版本：${this.versionInfo.currentVersion}`)
            .fontSize(13).margin({ bottom: 4 })
          Text(`最新版本：${this.versionInfo.latestVersion}`)
            .fontSize(13).margin({ bottom: 8 })
          Button('检测更新（需联网授权）')
            .width('100%').height(36).fontSize(13)
            .backgroundColor($r('app.color.primary_light'))
            .onClick(() => this.networkDialogController.open())

          // === 子板块4：开发者信息 ===
          this.SectionTitle('开发者信息与合规声明')
          Text(`微信：${ComplianceTexts.DEVELOPER_WECHAT}`)
            .fontSize(13).margin({ bottom: 4 })
          Text(`邮箱：${ComplianceTexts.DEVELOPER_EMAIL}`)
            .fontSize(13).margin({ bottom: 12 })
          Text(ComplianceTexts.STARTUP_DISCLAIMER)
            .fontSize(12).fontColor($r('app.color.text_secondary')).lineHeight(18)
            .margin({ bottom: 12 })
          Text(ComplianceTexts.COMMERCIAL_NOTICE)
            .fontSize(12).fontColor($r('app.color.warning')).lineHeight(18)
            .margin({ bottom: 8 })

          Text('查看完整免责声明 →')
            .fontSize(13)
            .fontColor($r('app.color.primary'))
            .decoration({ type: TextDecorationType.Underline })
            .margin({ bottom: 24 })
            .onClick(() => {
              NavigationHelper.push(this.uiContext, 'pages/DisclaimerPage');
            })

          if (this.statusMessage.length > 0) {
            Text(this.statusMessage)
              .fontSize(13).fontColor($r('app.color.success'))
              .textAlign(TextAlign.Center)
              .margin({ bottom: 16 })
          }
        }
        .padding({ left: 16, right: 16, bottom: 32 })
      }
      .layoutWeight(1)
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.background'))
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(16).fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.primary'))
      .width('100%')
      .margin({ top: 20, bottom: 12 })
  }
}
