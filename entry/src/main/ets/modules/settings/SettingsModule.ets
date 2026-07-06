/**
 * 模块8：独立设置配置模块（聚合入口）
 * 与其他业务模块完全解耦，可单独迭代
 */
import { UserProfile } from '../../common/types/AppTypes';
import { StorageKeys } from '../../common/constants/AppConstants';
import { LocalStorageUtil } from '../../common/utils/LocalStorageUtil';
import { MemberAuthModule } from './MemberAuthModule';
import { ModelConfigModule } from './ModelConfigModule';
import { VersionUpdateModule } from './VersionUpdateModule';

export class SettingsModule {
  readonly memberAuth: MemberAuthModule;
  readonly modelConfig: ModelConfigModule;
  readonly versionUpdate: VersionUpdateModule;

  constructor(memberAuth: MemberAuthModule, modelConfig: ModelConfigModule, versionUpdate: VersionUpdateModule) {
    this.memberAuth = memberAuth;
    this.modelConfig = modelConfig;
    this.versionUpdate = versionUpdate;
  }

  /** 保存用户基础信息（仅本地） */
  async saveUserProfile(profile: UserProfile): Promise<void> {
    await LocalStorageUtil.putString(StorageKeys.USER_PROFILE, JSON.stringify(profile));
  }

  /** 读取用户基础信息 */
  async getUserProfile(): Promise<UserProfile> {
    const saved = await LocalStorageUtil.getString(StorageKeys.USER_PROFILE, '');
    if (saved.length > 0) {
      try {
        return JSON.parse(saved) as UserProfile;
      } catch (err) {
        // 解析失败返回默认值
      }
    }
    return { nickname: '', gender: '未设置', age: 0 };
  }

  /** 清空用户基础信息 */
  async clearUserProfile(): Promise<void> {
    await LocalStorageUtil.remove(StorageKeys.USER_PROFILE);
  }
}
