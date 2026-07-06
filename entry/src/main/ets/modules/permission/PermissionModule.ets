/**
 * 模块1：权限管理模块
 * 负责相机、网络等权限的动态申请与降级提示
 */
import { abilityAccessCtrl, Permissions } from '@kit.AbilityKit';
import { common } from '@kit.AbilityKit';
import { IPermissionModule, PermissionResult } from '../../common/types/AppTypes';

export class PermissionModule implements IPermissionModule {
  private context: common.UIAbilityContext;
  private atManager: abilityAccessCtrl.AtManager;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
    this.atManager = abilityAccessCtrl.createAtManager();
  }

  /** 申请相机权限（必选，用于面部拍摄） */
  async requestCameraPermission(): Promise<PermissionResult> {
    const permission: Permissions = 'ohos.permission.CAMERA';
    return await this.requestSinglePermission(
      permission,
      '相机权限用于拍摄面部照片；经您授权后将上传至 AI 服务分析，完成后本地立即删除'
    );
  }

  /** 申请网络权限（可选，用于版本检测与联网模型） */
  async requestNetworkPermission(): Promise<PermissionResult> {
    const permission: Permissions = 'ohos.permission.INTERNET';
    return await this.requestSinglePermission(
      permission,
      '网络权限用于将照片上传至您配置的 AI 服务分析（需额外授权）；断网时使用本地规则兜底'
    );
  }

  /** 检查所有关键权限状态 */
  async checkAllPermissions(): Promise<Map<string, boolean>> {
    const result: Map<string, boolean> = new Map();
    const permissions: Permissions[] = [
      'ohos.permission.CAMERA',
      'ohos.permission.INTERNET',
      'ohos.permission.GET_NETWORK_INFO'
    ];

    for (const perm of permissions) {
      try {
        const status = await this.atManager.checkAccessToken(
          this.context.applicationInfo.accessTokenId,
          perm
        );
        result.set(perm, status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED);
      } catch (err) {
        console.error('[PermissionModule] checkAccessToken 失败', JSON.stringify(err));
        result.set(perm, false);
      }
    }
    return result;
  }

  /** 单个权限申请封装 */
  private async requestSinglePermission(
    permission: Permissions,
    purposeMessage: string
  ): Promise<PermissionResult> {
    try {
      const currentStatus = await this.atManager.checkAccessToken(
        this.context.applicationInfo.accessTokenId,
        permission
      );

      if (currentStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        return { granted: true, permissionName: permission, message: '权限已授予' };
      }

      const requestResult = await this.atManager.requestPermissionsFromUser(
        this.context,
        [permission]
      );

      const granted = requestResult.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
      return {
        granted: granted,
        permissionName: permission,
        message: granted ? '权限已授予' : `权限被拒绝：${purposeMessage}。部分功能将降级运行。`
      };
    } catch (err) {
      return {
        granted: false,
        permissionName: permission,
        message: `权限申请异常：${JSON.stringify(err)}`
      };
    }
  }
}
