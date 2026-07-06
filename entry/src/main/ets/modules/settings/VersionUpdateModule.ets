/**
 * 模块8子模块：版本更新检测
 * 需联网授权后方可检测，无授权则禁用
 */
import { AppVersion, RemoteApiConfig } from '../../common/constants/AppConstants';
import { VersionInfo } from '../../common/types/AppTypes';
import { HttpUtil } from '../../common/utils/HttpUtil';
import { NetworkAuthModule } from '../compliance/NetworkAuthModule';

/** 远程版本接口返回结构 */
interface RemoteVersionPayload {
  latestVersion?: string;
  versionCode?: number;
  updateLog?: string;
  hasUpdate?: boolean;
}

export class VersionUpdateModule {
  private networkAuth: NetworkAuthModule;

  constructor(networkAuth: NetworkAuthModule) {
    this.networkAuth = networkAuth;
  }

  /** 获取当前版本信息 */
  getCurrentVersionInfo(): VersionInfo {
    return {
      currentVersion: AppVersion.CURRENT,
      latestVersion: AppVersion.CURRENT,
      updateLog: '',
      hasUpdate: false
    };
  }

  /** 联网检测版本更新（需授权） */
  async checkForUpdate(): Promise<VersionInfo> {
    const current: VersionInfo = this.getCurrentVersionInfo();

    if (!this.networkAuth.canUseNetwork()) {
      return current;
    }

    try {
      const queryUrl =
        `${RemoteApiConfig.VERSION_CHECK_ENDPOINT}?current=${AppVersion.CURRENT}&code=${AppVersion.CODE}`;
      const response = await HttpUtil.get(queryUrl);
      if (!response.ok) {
        console.error('[VersionUpdate] 版本接口 HTTP 异常', response.statusCode);
        return current;
      }

      const remote = JSON.parse(response.body) as RemoteVersionPayload;
      const latestVersion = remote.latestVersion ?? AppVersion.CURRENT;
      const remoteCode = remote.versionCode ?? AppVersion.CODE;
      const hasUpdate = remote.hasUpdate ?? (remoteCode > AppVersion.CODE);

      return {
        currentVersion: AppVersion.CURRENT,
        latestVersion: latestVersion,
        updateLog: remote.updateLog ?? (hasUpdate ? '发现新版本，请前往应用市场更新' : '暂无新版本'),
        hasUpdate: hasUpdate
      };
    } catch (err) {
      console.error('[VersionUpdate] 检测失败', JSON.stringify(err));
      return current;
    }
  }
}
