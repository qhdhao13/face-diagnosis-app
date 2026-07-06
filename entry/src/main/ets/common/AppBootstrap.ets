/**
 * 应用启动引导
 * 初始化本地存储、注册全部模块到 ModuleRegistry
 */
import { common } from '@kit.AbilityKit';
import { LocalStorageUtil } from './utils/LocalStorageUtil';
import { ModuleRegistry } from './ModuleRegistry';
import { PermissionModule } from '../modules/permission/PermissionModule';
import { CameraModule } from '../modules/camera/CameraModule';
import { VisionModule } from '../modules/vision/VisionModule';
import { CloudVisionService } from '../services/CloudVisionService';
import { KnowledgeModule } from '../modules/knowledge/KnowledgeModule';
import { WellnessModule } from '../modules/wellness/WellnessModule';
import { ComplianceModule } from '../modules/compliance/ComplianceModule';
import { NetworkAuthModule } from '../modules/compliance/NetworkAuthModule';
import { MemberAuthModule } from '../modules/settings/MemberAuthModule';
import { PhoneAuthModule } from '../modules/auth/PhoneAuthModule';
import { ModelConfigModule } from '../modules/settings/ModelConfigModule';
import { VersionUpdateModule } from '../modules/settings/VersionUpdateModule';
import { SettingsModule } from '../modules/settings/SettingsModule';
import { TextGenerationService } from '../services/TextGenerationService';
import { ExperienceProxyService } from '../services/ExperienceProxyService';
import { DiagnosisOrchestrator } from '../services/DiagnosisOrchestrator';
import { DiagnosisReport, Region25SessionResult } from './types/AppTypes';

/** 全局应用状态（报告传递等） */
export class AppState {
  static currentReport: DiagnosisReport | null = null;
  /** 最近一次 25 色部云端会话（图片存服务器） */
  static currentRegion25: Region25SessionResult | null = null;
  static settingsModule: SettingsModule | null = null;
  static orchestrator: DiagnosisOrchestrator | null = null;
  static complianceModule: ComplianceModule | null = null;
  static networkAuthModule: NetworkAuthModule | null = null;
  static isInitialized: boolean = false;
  static initPromise: Promise<void> | null = null;
}

export class AppBootstrap {
  /** 应用启动时调用，完成全部模块注册 */
  static initialize(context: common.UIAbilityContext): Promise<void> {
    if (AppState.initPromise !== null) {
      return AppState.initPromise;
    }
    AppState.initPromise = AppBootstrap.doInitialize(context);
    return AppState.initPromise;
  }

  private static async doInitialize(context: common.UIAbilityContext): Promise<void> {
    await LocalStorageUtil.init(context);

    // 模块1：权限管理
    ModuleRegistry.registerPermission(new PermissionModule(context));

    // 模块2：相机采集
    ModuleRegistry.registerCamera(new CameraModule());

    // 模块7：合规风控
    const compliance = new ComplianceModule();
    ModuleRegistry.registerCompliance(compliance);
    AppState.complianceModule = compliance;

    // 联网授权
    const networkAuth = new NetworkAuthModule();
    ModuleRegistry.registerNetworkAuth(networkAuth);
    AppState.networkAuthModule = networkAuth;

    // 模块8：设置配置
    const memberAuth = new MemberAuthModule();
    ModuleRegistry.registerMemberAuth(memberAuth);

    const phoneAuth = new PhoneAuthModule();
    ModuleRegistry.registerPhoneAuth(phoneAuth);

    const modelConfig = new ModelConfigModule(memberAuth);
    ModuleRegistry.registerModelConfig(modelConfig);

    const experienceProxy = new ExperienceProxyService(phoneAuth);
    const cloudVision = new CloudVisionService(
      modelConfig, networkAuth, compliance, phoneAuth, experienceProxy
    );
    const vision = new VisionModule(cloudVision);
    await vision.initModels(context);
    ModuleRegistry.registerVision(vision);

    // 模块4：古籍知识库
    ModuleRegistry.registerKnowledge(new KnowledgeModule());

    // 模块5：养生方案
    ModuleRegistry.registerWellness(new WellnessModule());

    const versionUpdate = new VersionUpdateModule(networkAuth);
    AppState.settingsModule = new SettingsModule(memberAuth, modelConfig, versionUpdate);

    // 文案生成服务
    const textGen = new TextGenerationService(
      modelConfig, networkAuth, compliance, phoneAuth, experienceProxy
    );
    AppState.orchestrator = new DiagnosisOrchestrator(textGen);
    AppState.isInitialized = true;
  }
}
