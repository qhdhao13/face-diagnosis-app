/**
 * 页面导航工具
 * 使用 UIContext.getRouter()，替代已弃用的全局 router API
 */
export class NavigationHelper {
  /** 跳转到指定页面 */
  static push(uiContext: UIContext, url: string): void {
    try {
      uiContext.getRouter().pushUrl({ url: url });
    } catch (err) {
      console.error('[NavigationHelper] 跳转失败', JSON.stringify(err));
    }
  }

  /** 返回上一页 */
  static back(uiContext: UIContext): void {
    try {
      uiContext.getRouter().back();
    } catch (err) {
      console.error('[NavigationHelper] 返回失败', JSON.stringify(err));
    }
  }
}
