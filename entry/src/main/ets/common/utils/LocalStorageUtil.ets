/**
 * 本地持久化工具
 * 使用 Preferences 存储用户配置，面部图像数据禁止写入
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'face_diagnosis_app_store';

export class LocalStorageUtil {
  private static dataPreferences: preferences.Preferences | null = null;

  /** 初始化 Preferences 实例 */
  static async init(context: common.UIAbilityContext): Promise<void> {
    if (LocalStorageUtil.dataPreferences === null) {
      try {
        LocalStorageUtil.dataPreferences = await preferences.getPreferences(context, STORE_NAME);
      } catch (err) {
        console.error('[LocalStorageUtil] 初始化失败', JSON.stringify(err));
      }
    }
  }

  /** 写入字符串 */
  static async putString(key: string, value: string): Promise<void> {
    if (LocalStorageUtil.dataPreferences === null) {
      return;
    }
    try {
      await LocalStorageUtil.dataPreferences.put(key, value);
      await LocalStorageUtil.dataPreferences.flush();
    } catch (err) {
      console.error('[LocalStorageUtil] putString 失败', JSON.stringify(err));
    }
  }

  /** 读取字符串 */
  static async getString(key: string, defaultValue: string = ''): Promise<string> {
    if (LocalStorageUtil.dataPreferences === null) {
      return defaultValue;
    }
    try {
      return await LocalStorageUtil.dataPreferences.get(key, defaultValue) as string;
    } catch (err) {
      console.error('[LocalStorageUtil] getString 失败', JSON.stringify(err));
      return defaultValue;
    }
  }

  /** 写入布尔值 */
  static async putBoolean(key: string, value: boolean): Promise<void> {
    if (LocalStorageUtil.dataPreferences === null) {
      return;
    }
    try {
      await LocalStorageUtil.dataPreferences.put(key, value);
      await LocalStorageUtil.dataPreferences.flush();
    } catch (err) {
      console.error('[LocalStorageUtil] putBoolean 失败', JSON.stringify(err));
    }
  }

  /** 读取布尔值 */
  static async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    if (LocalStorageUtil.dataPreferences === null) {
      return defaultValue;
    }
    try {
      return await LocalStorageUtil.dataPreferences.get(key, defaultValue) as boolean;
    } catch (err) {
      console.error('[LocalStorageUtil] getBoolean 失败', JSON.stringify(err));
      return defaultValue;
    }
  }

  /** 删除指定键 */
  static async remove(key: string): Promise<void> {
    if (LocalStorageUtil.dataPreferences === null) {
      return;
    }
    try {
      await LocalStorageUtil.dataPreferences.delete(key);
      await LocalStorageUtil.dataPreferences.flush();
    } catch (err) {
      console.error('[LocalStorageUtil] remove 失败', JSON.stringify(err));
    }
  }

  /** 清空所有本地数据（不含运行时内存） */
  static async clearAll(): Promise<void> {
    if (LocalStorageUtil.dataPreferences === null) {
      return;
    }
    try {
      await LocalStorageUtil.dataPreferences.clear();
      await LocalStorageUtil.dataPreferences.flush();
    } catch (err) {
      console.error('[LocalStorageUtil] clearAll 失败', JSON.stringify(err));
    }
  }
}
