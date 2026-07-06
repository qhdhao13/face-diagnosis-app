/**
 * 模块7：合规隐私&风控模块
 * 医疗敏感词过滤、免责弹窗、隐私合规管控
 */
import { ComplianceTexts, SensitiveWords, StorageKeys } from '../../common/constants/AppConstants';
import { LocalStorageUtil } from '../../common/utils/LocalStorageUtil';
import { IComplianceModule } from '../../common/types/AppTypes';

export class ComplianceModule implements IComplianceModule {
  /** 过滤医疗敏感词，替换为合规表述 */
  filterSensitiveWords(text: string): string {
    let filtered = text;
    for (const word of SensitiveWords.BLOCK_LIST) {
      const regex = new RegExp(word, 'g');
      filtered = filtered.replace(regex, '**');
    }
    return filtered;
  }

  /** 校验输出文本是否包含敏感词 */
  validateOutput(text: string): boolean {
    for (const word of SensitiveWords.BLOCK_LIST) {
      if (text.includes(word)) {
        return false;
      }
    }
    return true;
  }

  /** 获取固定免责声明 */
  getDisclaimer(): string {
    return ComplianceTexts.REPORT_FOOTER;
  }

  /** 是否需要显示启动免责弹窗 */
  async shouldShowStartupDisclaimer(): Promise<boolean> {
    const accepted = await LocalStorageUtil.getBoolean(StorageKeys.DISCLAIMER_ACCEPTED, false);
    return !accepted;
  }

  /** 标记用户已接受免责声明 */
  async markDisclaimerAccepted(): Promise<void> {
    await LocalStorageUtil.putBoolean(StorageKeys.DISCLAIMER_ACCEPTED, true);
  }

  /** 获取完整隐私政策文本 */
  getPrivacyPolicy(): string {
    return ComplianceTexts.PRIVACY_POLICY;
  }

  /** 获取商用权限声明 */
  getCommercialNotice(): string {
    return ComplianceTexts.COMMERCIAL_NOTICE;
  }

  /** 获取启动免责声明全文 */
  getStartupDisclaimer(): string {
    return ComplianceTexts.STARTUP_DISCLAIMER;
  }
}
