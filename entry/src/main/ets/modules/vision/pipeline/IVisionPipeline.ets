/**
 * 视觉分析管线接口
 * 规则引擎与 .om 三模型管线均实现此接口，供 VisionModule 编排
 */
import { common } from '@kit.AbilityKit';
import { CapturedImage, FaceAppearanceFeature } from '../../../common/types/AppTypes';

export interface IVisionPipeline {
  /** 管线初始化 */
  init(context: common.UIAbilityContext): Promise<void>;
  /** 管线是否可用 */
  isReady(): boolean;
  /** 引擎展示名称 */
  getEngineLabel(): string;
  /** 分析人脸；失败返回 null 供上层降级 */
  analyze(captured: CapturedImage): Promise<FaceAppearanceFeature | null>;
}
