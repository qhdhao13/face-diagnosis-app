import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppBootstrap } from '../common/AppBootstrap';

const DOMAIN = 0x0001;
const TAG = 'EntryAbility';

/** 卡片/外部跳转允许打开的安全页面白名单 */
const ALLOWED_LAUNCH_PAGES: string[] = [
  'pages/Index',
  'pages/ScanPage',
  'pages/SettingsPage',
  'pages/PrivacyPage',
  'pages/DisclaimerPage'
];

export default class EntryAbility extends UIAbility {
  /** 启动或卡片跳转传入的 Want（避免与 UIAbility 基类属性冲突） */
  private startupWant: Want | null = null;
  /** 缓存 WindowStage，卡片二次跳转时用 loadContent（替代已弃用的 Window.loadContent） */
  private windowStageRef: window.WindowStage | null = null;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, '应用启动');
    this.startupWant = want;
    AppBootstrap.initialize(this.context);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.startupWant = want;
    const targetPage = EntryAbility.resolveLaunchPage(want);
    if (targetPage !== 'pages/Index' && this.windowStageRef !== null) {
      this.windowStageRef.loadContent(targetPage, (err) => {
        if (err.code) {
          hilog.error(DOMAIN, TAG, '跳转页面失败: %{public}s', JSON.stringify(err));
        }
      });
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '应用销毁');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.windowStageRef = windowStage;
    const targetPage = EntryAbility.resolveLaunchPage(this.startupWant);
    windowStage.loadContent(targetPage, (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, '加载页面失败: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, '页面加载成功: %{public}s', targetPage);
    });
  }

  /** 从 Want 参数解析安全的目标页面 */
  private static resolveLaunchPage(want: Want | null): string {
    if (want === null || want.parameters === undefined) {
      return 'pages/Index';
    }
    const urlParam = want.parameters['url'];
    if (typeof urlParam === 'string' && ALLOWED_LAUNCH_PAGES.includes(urlParam)) {
      return urlParam;
    }
    return 'pages/Index';
  }

  onWindowStageDestroy(): void {
    this.windowStageRef = null;
    hilog.info(DOMAIN, TAG, '窗口销毁');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '进入前台');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '进入后台');
  }
}
