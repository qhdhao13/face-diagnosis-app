import { FormExtensionAbility } from '@kit.FormKit';
import { formBindingData, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'WellnessFormAbility';

/** 元服务卡片扩展能力 */
export default class WellnessFormAbility extends FormExtensionAbility {
  onAddForm(want: Want): formBindingData.FormBindingData {
    hilog.info(DOMAIN, TAG, '添加卡片');
    const formData: Record<string, string> = {
      'title': '古籍面诊养生',
      'subtitle': '传统文化自测工具',
      'tip': '点击开始自测'
    };
    return formBindingData.createFormBindingData(formData);
  }

  onCastToNormalForm(formId: string): void {
    hilog.info(DOMAIN, TAG, '转为普通卡片: %{public}s', formId);
  }

  onUpdateForm(formId: string): void {
    hilog.info(DOMAIN, TAG, '更新卡片: %{public}s', formId);
  }

  onChangeFormVisibility(newStatus: Record<string, number>): void {
    hilog.info(DOMAIN, TAG, '卡片可见性变化');
  }

  onFormEvent(formId: string, message: string): void {
    hilog.info(DOMAIN, TAG, '卡片事件: %{public}s', message);
    // 卡片 postCardAction 触发的路由事件由系统分发，此处仅记录日志
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, '移除卡片: %{public}s', formId);
  }

  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
