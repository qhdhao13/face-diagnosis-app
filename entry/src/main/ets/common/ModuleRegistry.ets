/**
 * 模块注册中心
 * 各业务模块通过单例注册，实现完全解耦的可插拔架构
 */
import { ICameraModule } from './types/AppTypes';
import { IComplianceModule } from './types/AppTypes';
import { IKnowledgeModule } from './types/AppTypes';
import { IMemberAuthModule } from './types/AppTypes';
import { IPhoneAuthModule } from './types/AppTypes';
import { IModelConfigModule } from './types/AppTypes';
import { INetworkAuthModule } from './types/AppTypes';
import { IPermissionModule } from './types/AppTypes';
import { IVisionModule } from './types/AppTypes';
import { IWellnessModule } from './types/AppTypes';

export class ModuleRegistry {
  private static permissionModule: IPermissionModule | null = null;
  private static cameraModule: ICameraModule | null = null;
  private static visionModule: IVisionModule | null = null;
  private static knowledgeModule: IKnowledgeModule | null = null;
  private static wellnessModule: IWellnessModule | null = null;
  private static complianceModule: IComplianceModule | null = null;
  private static networkAuthModule: INetworkAuthModule | null = null;
  private static modelConfigModule: IModelConfigModule | null = null;
  private static memberAuthModule: IMemberAuthModule | null = null;
  private static phoneAuthModule: IPhoneAuthModule | null = null;

  static registerPermission(module: IPermissionModule): void {
    ModuleRegistry.permissionModule = module;
  }

  static registerCamera(module: ICameraModule): void {
    ModuleRegistry.cameraModule = module;
  }

  static registerVision(module: IVisionModule): void {
    ModuleRegistry.visionModule = module;
  }

  static registerKnowledge(module: IKnowledgeModule): void {
    ModuleRegistry.knowledgeModule = module;
  }

  static registerWellness(module: IWellnessModule): void {
    ModuleRegistry.wellnessModule = module;
  }

  static registerCompliance(module: IComplianceModule): void {
    ModuleRegistry.complianceModule = module;
  }

  static registerNetworkAuth(module: INetworkAuthModule): void {
    ModuleRegistry.networkAuthModule = module;
  }

  static registerModelConfig(module: IModelConfigModule): void {
    ModuleRegistry.modelConfigModule = module;
  }

  static registerMemberAuth(module: IMemberAuthModule): void {
    ModuleRegistry.memberAuthModule = module;
  }

  static registerPhoneAuth(module: IPhoneAuthModule): void {
    ModuleRegistry.phoneAuthModule = module;
  }

  static getPermission(): IPermissionModule {
    if (ModuleRegistry.permissionModule === null) {
      throw new Error('权限模块未注册');
    }
    return ModuleRegistry.permissionModule;
  }

  static getCamera(): ICameraModule {
    if (ModuleRegistry.cameraModule === null) {
      throw new Error('相机模块未注册');
    }
    return ModuleRegistry.cameraModule;
  }

  static getVision(): IVisionModule {
    if (ModuleRegistry.visionModule === null) {
      throw new Error('视觉识别模块未注册');
    }
    return ModuleRegistry.visionModule;
  }

  static getKnowledge(): IKnowledgeModule {
    if (ModuleRegistry.knowledgeModule === null) {
      throw new Error('古籍知识库模块未注册');
    }
    return ModuleRegistry.knowledgeModule;
  }

  static getWellness(): IWellnessModule {
    if (ModuleRegistry.wellnessModule === null) {
      throw new Error('养生方案模块未注册');
    }
    return ModuleRegistry.wellnessModule;
  }

  static getCompliance(): IComplianceModule {
    if (ModuleRegistry.complianceModule === null) {
      throw new Error('合规模块未注册');
    }
    return ModuleRegistry.complianceModule;
  }

  static getNetworkAuth(): INetworkAuthModule {
    if (ModuleRegistry.networkAuthModule === null) {
      throw new Error('联网授权模块未注册');
    }
    return ModuleRegistry.networkAuthModule;
  }

  static getModelConfig(): IModelConfigModule {
    if (ModuleRegistry.modelConfigModule === null) {
      throw new Error('模型配置模块未注册');
    }
    return ModuleRegistry.modelConfigModule;
  }

  static getMemberAuth(): IMemberAuthModule {
    if (ModuleRegistry.memberAuthModule === null) {
      throw new Error('会员模块未注册');
    }
    return ModuleRegistry.memberAuthModule;
  }

  static getPhoneAuth(): IPhoneAuthModule {
    if (ModuleRegistry.phoneAuthModule === null) {
      throw new Error('手机号模块未注册');
    }
    return ModuleRegistry.phoneAuthModule;
  }
}
