/**
 * 模块8子模块：会员权限校验
 * 方案 A（内测）：VIP_ 前缀会员 ID 自动审批，由开发者发放 ID
 */
import { IMemberAuthModule, MemberAuthStatus } from '../../common/types/AppTypes';
import { MemberConfig, StorageKeys } from '../../common/constants/AppConstants';
import { LocalStorageUtil } from '../../common/utils/LocalStorageUtil';

export class MemberAuthModule implements IMemberAuthModule {
  private status: MemberAuthStatus = {
    isRegistered: false,
    isApproved: false,
    memberId: ''
  };

  constructor() {
    this.loadStatus();
  }

  /** 从本地加载会员状态 */
  private async loadStatus(): Promise<void> {
    const saved = await LocalStorageUtil.getString(StorageKeys.MEMBER_AUTH, '');
    if (saved.length > 0) {
      try {
        this.status = JSON.parse(saved) as MemberAuthStatus;
        // 加载后按 VIP_ 规则同步审批（防止旧数据不一致）
        MemberAuthModule.applyVipApprovalRule(this.status);
      } catch (err) {
        console.error('[MemberAuth] 解析会员状态失败');
      }
    }
  }

  getStatus(): MemberAuthStatus {
    return this.status;
  }

  /** 注册会员（本地记录；VIP_ 前缀自动审批） */
  async registerMember(memberId: string): Promise<boolean> {
    const trimmed = memberId.trim();
    if (trimmed.length < MemberConfig.MIN_ID_LENGTH) {
      return false;
    }
    this.status.isRegistered = true;
    this.status.memberId = trimmed;
    MemberAuthModule.applyVipApprovalRule(this.status);
    await this.saveStatus();
    return true;
  }

  /**
   * 刷新审批状态（设置页可手动触发）
   * 重新按 VIP_ 规则判定是否通过
   */
  async refreshApproval(): Promise<boolean> {
    await this.loadStatus();
    if (!this.status.isRegistered || this.status.memberId.length === 0) {
      return false;
    }
    MemberAuthModule.applyVipApprovalRule(this.status);
    await this.saveStatus();
    return this.status.isApproved;
  }

  /** 检查审批状态 */
  async checkApproval(): Promise<boolean> {
    await this.loadStatus();
    return this.status.isRegistered && this.status.isApproved;
  }

  /** 方案 A：VIP_ 前缀内测 ID 自动通过 */
  private static applyVipApprovalRule(status: MemberAuthStatus): void {
    if (status.memberId.startsWith(MemberConfig.VIP_PREFIX)) {
      status.isApproved = true;
    } else {
      status.isApproved = false;
    }
  }

  /** 保存会员状态到本地 */
  private async saveStatus(): Promise<void> {
    await LocalStorageUtil.putString(StorageKeys.MEMBER_AUTH, JSON.stringify(this.status));
  }

  /** 清除会员信息 */
  async clearMember(): Promise<void> {
    this.status = { isRegistered: false, isApproved: false, memberId: '' };
    await LocalStorageUtil.remove(StorageKeys.MEMBER_AUTH);
  }
}
