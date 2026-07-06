/**
 * 手机号注册与白名单体验配额
 * 体验免 Key：服务端校验白名单 + 每日 2 次；自带 Key：仅要求注册手机号
 */
import { IPhoneAuthModule, PhoneAuthStatus } from '../../common/types/AppTypes';
import { ExperienceServerConfig, StorageKeys } from '../../common/constants/AppConstants';
import { LocalStorageUtil } from '../../common/utils/LocalStorageUtil';
import { HttpUtil } from '../../common/utils/HttpUtil';

class PhoneRegisterRequest {
  phone: string = '';
}

class PhoneAuthResponseBody {
  ok?: boolean;
  token?: string;
  phone?: string;
  isWhitelisted?: boolean;
  dailyFreeLimit?: number;
  dailyFreeRemaining?: number;
  message?: string;
}

class PhoneConsumeResponseBody {
  ok?: boolean;
  dailyFreeRemaining?: number;
  message?: string;
}

export class PhoneAuthModule implements IPhoneAuthModule {
  private status: PhoneAuthStatus = PhoneAuthModule.emptyStatus();

  constructor() {
    this.loadStatus();
  }

  private static emptyStatus(): PhoneAuthStatus {
    return {
      phoneNumber: '',
      isRegistered: false,
      isWhitelisted: false,
      authToken: '',
      dailyFreeLimit: ExperienceServerConfig.DAILY_FREE_LIMIT,
      dailyFreeRemaining: 0
    };
  }

  private async loadStatus(): Promise<void> {
    const saved = await LocalStorageUtil.getString(StorageKeys.PHONE_AUTH, '');
    if (saved.length > 0) {
      try {
        this.status = JSON.parse(saved) as PhoneAuthStatus;
      } catch (_err) {
        this.status = PhoneAuthModule.emptyStatus();
      }
    }
  }

  private async saveStatus(): Promise<void> {
    await LocalStorageUtil.putString(StorageKeys.PHONE_AUTH, JSON.stringify(this.status));
  }

  getStatus(): PhoneAuthStatus {
    return this.status;
  }

  getAuthToken(): string {
    return this.status.authToken;
  }

  isPhoneRegistered(): boolean {
    return this.status.isRegistered && this.status.phoneNumber.length > 0 && this.status.authToken.length > 0;
  }

  canUseExperience(): boolean {
    return this.isPhoneRegistered()
      && this.status.isWhitelisted
      && this.status.dailyFreeRemaining > 0;
  }

  canUseByok(): boolean {
    return this.isPhoneRegistered();
  }

  /** 中国大陆 11 位手机号校验 */
  static isValidPhone(phone: string): boolean {
    const trimmed = phone.trim();
    if (trimmed.length !== 11) {
      return false;
    }
    if (trimmed.charAt(0) !== '1') {
      return false;
    }
    for (let i = 0; i < trimmed.length; i++) {
      const c = trimmed.charAt(i);
      if (c < '0' || c > '9') {
        return false;
      }
    }
    return true;
  }

  async registerPhone(phoneNumber: string): Promise<boolean> {
    const phone = phoneNumber.trim();
    if (!PhoneAuthModule.isValidPhone(phone)) {
      return false;
    }

    const req = new PhoneRegisterRequest();
    req.phone = phone;
    const url = `${ExperienceServerConfig.BASE_URL}${ExperienceServerConfig.REGISTER_PATH}`;
    const response = await HttpUtil.post(url, JSON.stringify(req), {
      'Content-Type': 'application/json'
    }, 15000);

    if (!response.ok) {
      console.error('[PhoneAuth] 注册失败', response.statusCode, response.body);
      return false;
    }

    let parsed: PhoneAuthResponseBody;
    try {
      parsed = JSON.parse(response.body) as PhoneAuthResponseBody;
    } catch (_err) {
      return false;
    }

    if (parsed.ok !== true || parsed.token === undefined || parsed.token.length === 0) {
      return false;
    }

    this.status.phoneNumber = phone;
    this.status.isRegistered = true;
    this.status.authToken = parsed.token;
    this.status.isWhitelisted = parsed.isWhitelisted === true;
    this.status.dailyFreeLimit = parsed.dailyFreeLimit ?? ExperienceServerConfig.DAILY_FREE_LIMIT;
    this.status.dailyFreeRemaining = parsed.dailyFreeRemaining ?? 0;
    await this.saveStatus();
    return true;
  }

  async refreshStatus(): Promise<boolean> {
    if (!this.isPhoneRegistered()) {
      return false;
    }

    const url = `${ExperienceServerConfig.BASE_URL}${ExperienceServerConfig.STATUS_PATH}`;
    const response = await HttpUtil.get(url, {
      'Authorization': `Bearer ${this.status.authToken}`
    });

    if (!response.ok) {
      console.error('[PhoneAuth] 刷新状态失败', response.statusCode);
      return false;
    }

    let parsed: PhoneAuthResponseBody;
    try {
      parsed = JSON.parse(response.body) as PhoneAuthResponseBody;
    } catch (_err) {
      return false;
    }

    this.status.isWhitelisted = parsed.isWhitelisted === true;
    this.status.dailyFreeLimit = parsed.dailyFreeLimit ?? this.status.dailyFreeLimit;
    this.status.dailyFreeRemaining = parsed.dailyFreeRemaining ?? this.status.dailyFreeRemaining;
    await this.saveStatus();
    return true;
  }

  async consumeQuota(): Promise<boolean> {
    if (!this.canUseExperience()) {
      return false;
    }

    const url = `${ExperienceServerConfig.BASE_URL}${ExperienceServerConfig.CONSUME_PATH}`;
    const response = await HttpUtil.post(url, '{}', {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.status.authToken}`
    }, 15000);

    if (!response.ok) {
      console.error('[PhoneAuth] 扣减配额失败', response.statusCode, response.body);
      return false;
    }

    let parsed: PhoneConsumeResponseBody;
    try {
      parsed = JSON.parse(response.body) as PhoneConsumeResponseBody;
    } catch (_err) {
      return false;
    }

    if (parsed.ok !== true) {
      return false;
    }

    if (parsed.dailyFreeRemaining !== undefined) {
      this.status.dailyFreeRemaining = parsed.dailyFreeRemaining;
      await this.saveStatus();
    }
    return true;
  }
}
