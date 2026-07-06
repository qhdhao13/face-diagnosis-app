/**
 * 模块8子模块：模型配置中心
 * 支持官方推荐模型 / 私有会员模型双切换
 */
import { DefaultModelConfig, StorageKeys } from '../../common/constants/AppConstants';
import { LocalStorageUtil } from '../../common/utils/LocalStorageUtil';
import { ApiEndpointUtil } from '../../common/utils/ApiEndpointUtil';
import { IModelConfigModule, ModelConfig, ModelType, ModelUsageMode } from '../../common/types/AppTypes';
import { MemberAuthModule } from './MemberAuthModule';

export class ModelConfigModule implements IModelConfigModule {
  private config: ModelConfig;
  private memberAuth: MemberAuthModule;

  constructor(memberAuth: MemberAuthModule) {
    this.memberAuth = memberAuth;
    this.config = this.getDefaultConfig();
    this.loadConfig();
  }

  /** 获取默认官方推荐配置 */
  private getDefaultConfig(): ModelConfig {
    return {
      modelType: ModelType.OFFICIAL,
      apiEndpoint: DefaultModelConfig.OFFICIAL_ENDPOINT,
      apiPort: 443,
      apiKey: '',
      visionModelName: DefaultModelConfig.OFFICIAL_VISION_MODEL_NAME,
      privateToken: '',
      isOfficialRecommended: true,
      usageMode: ModelUsageMode.EXPERIENCE
    };
  }

  /** 从本地加载配置 */
  private async loadConfig(): Promise<void> {
    const saved = await LocalStorageUtil.getString(StorageKeys.MODEL_CONFIG, '');
    if (saved.length > 0) {
      try {
        this.config = JSON.parse(saved) as ModelConfig;
        if (this.config.visionModelName === undefined || this.config.visionModelName.length === 0) {
          this.config.visionModelName = DefaultModelConfig.OFFICIAL_VISION_MODEL_NAME;
        }
        if (this.config.apiKey === undefined) {
          this.config.apiKey = '';
        }
        this.config.apiEndpoint = ApiEndpointUtil.normalizeChatCompletionsEndpoint(this.config.apiEndpoint);
        if (this.config.usageMode === undefined) {
          this.config.usageMode = ModelUsageMode.EXPERIENCE;
        }
      } catch (err) {
        this.config = this.getDefaultConfig();
      }
    }
  }

  getConfig(): ModelConfig {
    return this.config;
  }

  /** 保存模型配置（本地加密缓存） */
  async saveConfig(config: ModelConfig): Promise<void> {
    // 选择私有模型时校验会员权限
    if (config.modelType === ModelType.PRIVATE) {
      const hasAccess = await this.validatePrivateModelAccess();
      if (!hasAccess) {
        throw new Error('私有模型权限不足：需完成会员注册并经开发者审批');
      }
    }
    this.config = config;
    this.config.apiEndpoint = ApiEndpointUtil.normalizeChatCompletionsEndpoint(this.config.apiEndpoint);
    await LocalStorageUtil.putString(StorageKeys.MODEL_CONFIG, JSON.stringify(this.config));
  }

  /** 一键恢复默认官方推荐配置 */
  async resetToDefault(): Promise<void> {
    this.config = this.getDefaultConfig();
    await LocalStorageUtil.putString(StorageKeys.MODEL_CONFIG, JSON.stringify(this.config));
  }

  /** 校验私有模型访问权限 */
  async validatePrivateModelAccess(): Promise<boolean> {
    return await this.memberAuth.checkApproval();
  }
}
