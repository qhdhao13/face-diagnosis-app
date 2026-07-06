/**
 * 联网授权模块
 * 所有联网操作需用户主动授权，拒绝后锁定联网功能
 */
import { NetworkAuthLevel } from '../../common/types/AppTypes';
import { StorageKeys } from '../../common/constants/AppConstants';
import { LocalStorageUtil } from '../../common/utils/LocalStorageUtil';
import { INetworkAuthModule } from '../../common/types/AppTypes';

export class NetworkAuthModule implements INetworkAuthModule {
  private currentAuthLevel: NetworkAuthLevel = NetworkAuthLevel.DENY;
  private sessionAuthorized: boolean = false;

  constructor() {
    this.loadAuthLevel();
  }

  /** 从本地加载授权级别 */
  private async loadAuthLevel(): Promise<void> {
    const saved = await LocalStorageUtil.getString(StorageKeys.NETWORK_AUTH, NetworkAuthLevel.DENY);
    this.currentAuthLevel = saved as NetworkAuthLevel;
  }

  getAuthLevel(): NetworkAuthLevel {
    return this.currentAuthLevel;
  }

  /** 是否允许使用网络 */
  canUseNetwork(): boolean {
    if (this.currentAuthLevel === NetworkAuthLevel.ALWAYS) {
      return true;
    }
    if (this.currentAuthLevel === NetworkAuthLevel.ONCE && this.sessionAuthorized) {
      return true;
    }
    return false;
  }

  /** 标记本次会话已授权（单次授权模式） */
  markSessionAuthorized(): void {
    this.sessionAuthorized = true;
  }

  /** 保存授权级别到本地 */
  async saveAuthLevel(level: NetworkAuthLevel): Promise<void> {
    this.currentAuthLevel = level;
    await LocalStorageUtil.putString(StorageKeys.NETWORK_AUTH, level);
    if (level === NetworkAuthLevel.ONCE) {
      this.sessionAuthorized = true;
    }
  }

  /**
   * 请求联网授权（由UI层弹窗后调用）
   * 返回用户选择的授权级别
   */
  async requestNetworkAuth(): Promise<NetworkAuthLevel> {
    // 实际授权选择由 UI 弹窗完成，此处返回当前级别
    return this.currentAuthLevel;
  }

  /** 重置联网授权 */
  async resetAuth(): Promise<void> {
    this.currentAuthLevel = NetworkAuthLevel.DENY;
    this.sessionAuthorized = false;
    await LocalStorageUtil.putString(StorageKeys.NETWORK_AUTH, NetworkAuthLevel.DENY);
  }
}
