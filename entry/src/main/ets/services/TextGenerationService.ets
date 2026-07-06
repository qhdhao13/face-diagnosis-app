/**
 * 古籍双译文案生成服务
 * 支持官方通用模型 / 私有会员模型双模式
 * 断网时自动降级离线古籍解析
 */
import {
  AncientTextEntry,
  FaceAppearanceFeature,
  ModelConfig,
  ModelType,
  ModelUsageMode,
  TextGenerationRequest,
  TextGenerationResponse,
  UserProfile
} from '../common/types/AppTypes';
import { DefaultModelConfig } from '../common/constants/AppConstants';
import { HttpUtil } from '../common/utils/HttpUtil';
import { ApiEndpointUtil } from '../common/utils/ApiEndpointUtil';
import { ComplianceModule } from '../modules/compliance/ComplianceModule';
import { ModelConfigModule } from '../modules/settings/ModelConfigModule';
import { NetworkAuthModule } from '../modules/compliance/NetworkAuthModule';
import { PhoneAuthModule } from '../modules/auth/PhoneAuthModule';
import { ExperienceProxyService } from './ExperienceProxyService';

/** OpenAI 兼容 Chat Completions 请求/响应结构（ArkTS 需显式 class） */
class ChatRequestMessage {
  role: string = '';
  content: string = '';
}

class ChatRequestPayload {
  model: string = '';
  messages: ChatRequestMessage[] = [];
  temperature: number = 0.7;
}

class ChatResponseMessage {
  content?: string;
}

class ChatCompletionChoice {
  message?: ChatResponseMessage;
}

class ChatCompletionResponse {
  choices?: ChatCompletionChoice[];
}

export class TextGenerationService {
  private modelConfig: ModelConfigModule;
  private networkAuth: NetworkAuthModule;
  private compliance: ComplianceModule;
  private phoneAuth: PhoneAuthModule;
  private experienceProxy: ExperienceProxyService;

  constructor(
    modelConfig: ModelConfigModule,
    networkAuth: NetworkAuthModule,
    compliance: ComplianceModule,
    phoneAuth: PhoneAuthModule,
    experienceProxy: ExperienceProxyService
  ) {
    this.modelConfig = modelConfig;
    this.networkAuth = networkAuth;
    this.compliance = compliance;
    this.phoneAuth = phoneAuth;
    this.experienceProxy = experienceProxy;
  }

  /**
   * 生成古籍双译文案
   * 联网模式：调用选定模型 + RAG 古籍知识库
   * 离线模式：直接使用静态知识库
   */
  async generate(request: TextGenerationRequest): Promise<TextGenerationResponse> {
    const config = this.modelConfig.getConfig();
    const canNetwork = this.networkAuth.canUseNetwork();

    // 离线兜底或拒绝联网
    if (!canNetwork) {
      return this.generateOffline(request);
    }

    // 私有模型权限校验（体验模式不走私有）
    if (config.modelType === ModelType.PRIVATE && config.usageMode !== ModelUsageMode.EXPERIENCE) {
      const hasAccess = await this.modelConfig.validatePrivateModelAccess();
      if (!hasAccess) {
        return this.generateOffline(request);
      }
    }

    if (config.usageMode === ModelUsageMode.BYOK && !this.phoneAuth.canUseByok()) {
      return this.generateOffline(request);
    }

    if (config.usageMode === ModelUsageMode.EXPERIENCE && !this.phoneAuth.canUseExperience()) {
      return this.generateOffline(request);
    }

    try {
      return await this.generateOnline(request, config);
    } catch (err) {
      console.error('[TextGen] 联网生成失败，降级离线', JSON.stringify(err));
      return this.generateOffline(request);
    }
  }

  /** 联网模型生成（RAG + 古籍知识库约束 + HTTP API） */
  private async generateOnline(
    request: TextGenerationRequest,
    config: ModelConfig
  ): Promise<TextGenerationResponse> {
    const entries = request.ancientEntries;
    const ragContext = this.buildRagContext(entries);
    const userPrompt = this.buildUserPrompt(request.features, request.profile, ragContext);

    const systemPrompt =
      '你是古籍养生文化解读助手。请基于提供的古籍原文与现代释义，' +
      '用通俗易懂的语言给出养生观察参考。严禁使用任何医疗、诊疗、用药相关表述，' +
      '仅输出文化娱乐与日常养护参考内容。';

    if (config.usageMode === ModelUsageMode.EXPERIENCE) {
      const rawContent = await this.experienceProxy.generateText(systemPrompt, userPrompt);
      const filtered = this.compliance.filterSensitiveWords(rawContent);
      return {
        culturalInterpretation: `（体验免 Key 解读）\n${filtered}`,
        formattedReferences: entries,
        success: true,
        usedOfflineFallback: false
      };
    }

    const modelName = config.modelType === ModelType.OFFICIAL
      ? DefaultModelConfig.OFFICIAL_MODEL_NAME
      : 'private-face-diagnosis-v1';
    const authToken = config.modelType === ModelType.PRIVATE ? config.privateToken : config.apiKey;

    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    if (authToken.length > 0) {
      headers['Authorization'] = `Bearer ${authToken}`;
    }

    const systemMessage = new ChatRequestMessage();
    systemMessage.role = 'system';
    systemMessage.content = systemPrompt;

    const userMessage = new ChatRequestMessage();
    userMessage.role = 'user';
    userMessage.content = userPrompt;

    const payloadObj = new ChatRequestPayload();
    payloadObj.model = modelName;
    payloadObj.messages = [systemMessage, userMessage];
    payloadObj.temperature = 0.7;

    const payload = JSON.stringify(payloadObj);

    const requestUrl = ApiEndpointUtil.normalizeChatCompletionsEndpoint(config.apiEndpoint);
    const response = await HttpUtil.post(requestUrl, payload, headers);
    if (!response.ok) {
      throw new Error(`模型 API 请求失败，HTTP ${response.statusCode}`);
    }

    let parsed: ChatCompletionResponse;
    try {
      parsed = JSON.parse(response.body) as ChatCompletionResponse;
    } catch (err) {
      throw new Error('模型 API 返回非 JSON 格式');
    }

    const rawContent = parsed.choices?.[0]?.message?.content ?? '';
    if (rawContent.length === 0) {
      throw new Error('模型 API 返回空内容');
    }

    const modelLabel = config.modelType === ModelType.OFFICIAL ? '官方推荐模型' : '私有会员模型';
    const filtered = this.compliance.filterSensitiveWords(rawContent);

    return {
      culturalInterpretation: `（${modelLabel}解读）\n${filtered}`,
      formattedReferences: entries,
      success: true,
      usedOfflineFallback: false
    };
  }

  /** 拼接 RAG 古籍上下文 */
  private buildRagContext(entries: AncientTextEntry[]): string {
    const parts: string[] = [];
    for (const entry of entries) {
      parts.push(
        `【${entry.source}·${entry.chapter}】\n` +
        `原文：${entry.originalText}\n` +
        `释义：${entry.modernExplanation}`
      );
    }
    return parts.join('\n\n');
  }

  /** 构建发送给模型的用户提示词 */
  private buildUserPrompt(
    features: FaceAppearanceFeature,
    profile: UserProfile | undefined,
    ragContext: string
  ): string {
    const profileText = profile !== undefined
      ? `用户基础信息：昵称 ${profile.nickname}，性别 ${profile.gender}，年龄 ${profile.age}。\n`
      : '';

    return `${profileText}` +
      `面部外观客观描述：${features.overallComplexion}；` +
      `${features.forehead}；${features.leftCheek}；${features.rightCheek}；` +
      `${features.nose}；${features.chin}；${features.eyeArea}；${features.lipArea}。\n\n` +
      `请结合以下古籍条目给出养生文化解读：\n${ragContext}`;
  }

  /** 离线降级：直接使用静态古籍知识库 */
  private generateOffline(request: TextGenerationRequest): TextGenerationResponse {
    const entries = request.ancientEntries;
    const parts: string[] = ['（离线古籍解读）'];

    for (const entry of entries) {
      parts.push(
        `【${entry.source}·${entry.chapter}】\n` +
        `原文：${entry.originalText}\n` +
        `释义：${entry.modernExplanation}`
      );
    }

    const filtered = this.compliance.filterSensitiveWords(parts.join('\n\n'));

    return {
      culturalInterpretation: filtered,
      formattedReferences: entries,
      success: true,
      usedOfflineFallback: true
    };
  }
}
