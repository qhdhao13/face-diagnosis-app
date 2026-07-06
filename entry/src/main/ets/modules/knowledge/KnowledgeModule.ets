/**
 * 模块4：古籍知识库匹配模块（评分版）
 */
import { AncientTextEntry, FaceAppearanceFeature, IKnowledgeModule } from '../../common/types/AppTypes';
import { ANCIENT_KNOWLEDGE_BASE } from './AncientKnowledgeData';
import { KnowledgeMatchEngine } from './KnowledgeMatchEngine';

export class KnowledgeModule implements IKnowledgeModule {
  private knowledgeBase: AncientTextEntry[] = ANCIENT_KNOWLEDGE_BASE;
  private matchEngine: KnowledgeMatchEngine = new KnowledgeMatchEngine();

  /** 根据面部特征评分匹配古籍条目 */
  matchByFeatures(features: FaceAppearanceFeature): AncientTextEntry[] {
    return this.matchEngine.match(features, this.knowledgeBase, 5);
  }

  /** 离线兜底：按关键词返回最佳单条 */
  getOfflineFallback(featureKey: string): AncientTextEntry | null {
    const pseudoFeature: FaceAppearanceFeature = {
      overallComplexion: featureKey,
      forehead: featureKey,
      leftCheek: featureKey,
      rightCheek: featureKey,
      nose: featureKey,
      chin: featureKey,
      eyeArea: featureKey,
      lipArea: featureKey,
      details: [featureKey],
      confidence: 0.5,
      averageBrightness: 128,
      matchTags: [featureKey]
    };
    const matched = this.matchEngine.match(pseudoFeature, this.knowledgeBase, 1);
    return matched.length > 0 ? matched[0] : this.knowledgeBase[0];
  }
}
