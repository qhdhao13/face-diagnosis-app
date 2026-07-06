/**
 * 云端视觉分析服务
 * 通过 OpenAI 兼容多模态 API（如通义千问 VL）分析面部外观，返回结构化 FaceAppearanceFeature
 */
import { CapturedImage, FaceAppearanceFeature, ModelConfig, ModelType, ModelUsageMode, UserProfile } from '../common/types/AppTypes';
import { ComplexionTypes, DefaultModelConfig } from '../common/constants/AppConstants';
import { HttpUtil } from '../common/utils/HttpUtil';
import { ApiEndpointUtil } from '../common/utils/ApiEndpointUtil';
import { ImageBase64Util } from '../common/utils/ImageBase64Util';
import { ImageBrightnessUtil } from '../common/utils/ImageBrightnessUtil';
import { ComplianceModule } from '../modules/compliance/ComplianceModule';
import { ModelConfigModule } from '../modules/settings/ModelConfigModule';
import { NetworkAuthModule } from '../modules/compliance/NetworkAuthModule';
import { PhoneAuthModule } from '../modules/auth/PhoneAuthModule';
import { ExperienceProxyService } from './ExperienceProxyService';
import { Region25FeatureMapper } from '../modules/vision/Region25FeatureMapper';
import { AppState } from '../common/AppBootstrap';

/** 多模态消息片段 */
class VisionContentImageUrl {
  url: string = '';
}

class VisionContentImagePart {
  type: string = 'image_url';
  image_url: VisionContentImageUrl = new VisionContentImageUrl();
}

class VisionContentTextPart {
  type: string = 'text';
  text: string = '';
}

class VisionChatMessage {
  role: string = 'user';
  content: (VisionContentTextPart | VisionContentImagePart)[] = [];
}

/** 系统提示消息（纯文本） */
class VisionSystemMessage {
  role: string = 'system';
  content: string = '';
}

class VisionChatPayload {
  model: string = '';
  messages: (VisionSystemMessage | VisionChatMessage)[] = [];
  temperature: number = 0.2;
}

class VisionResponseMessage {
  content?: string;
}

class VisionResponseChoice {
  message?: VisionResponseMessage;
}

class VisionChatResponse {
  choices?: VisionResponseChoice[];
}

/** API 返回 JSON 字段（宽松解析） */
class CloudVisionJson {
  overallComplexion?: string;
  forehead?: string;
  leftCheek?: string;
  rightCheek?: string;
  nose?: string;
  chin?: string;
  eyeArea?: string;
  lipArea?: string;
  details?: string[];
  confidence?: number;
  averageBrightness?: number;
  matchTags?: string[];
}

export class CloudVisionService {
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

  /** 是否具备云端分析条件 */
  canUseCloudVision(): boolean {
    if (!this.networkAuth.canUseNetwork()) {
      return false;
    }
    const config = this.modelConfig.getConfig();
    if (config.usageMode === ModelUsageMode.EXPERIENCE) {
      return this.experienceProxy.isServerConfigured() && this.phoneAuth.canUseExperience();
    }
    const token = CloudVisionService.resolveAuthToken(config);
    return this.phoneAuth.canUseByok() && config.apiEndpoint.length > 0 && token.length > 0;
  }

  /**
   * 调用云端多模态模型分析面部
   * @throws 网络或解析失败时抛出，由 VisionModule 降级本地规则
   */
  async analyzeFace(captured: CapturedImage, profile?: UserProfile): Promise<FaceAppearanceFeature> {
    if (!this.canUseCloudVision()) {
      throw new Error('云端视觉未就绪：请注册手机号并检查模式/配额/Key');
    }

    const config = this.modelConfig.getConfig();
    if (config.usageMode === ModelUsageMode.EXPERIENCE) {
      const profileGender = profile?.gender;
      const session = await this.experienceProxy.analyzeRegion25(captured, profileGender);
      // 性别与设置不符时直接抛错，避免 ArkTS 对 AppState 侧效应的类型推断问题
      if (session.genderMismatch === true) {
        throw new Error(session.genderWarning ??
          '照片中面部性别特征与您在设置中填写的性别不一致，请核对后重拍');
      }
      AppState.currentRegion25 = session;
      const feature = Region25FeatureMapper.toFaceAppearanceFeature(session, 128);
      feature.analysisEngine = 'region25_cloud';
      return this.sanitizeFeature(feature);
    }

    if (!this.phoneAuth.canUseByok()) {
      throw new Error('自带 Key 模式须先注册手机号');
    }
    const base64 = await ImageBase64Util.toJpegBase64(captured);
    const imageUrl = `data:image/jpeg;base64,${base64}`;

    const visionModel = config.visionModelName.length > 0
      ? config.visionModelName
      : DefaultModelConfig.OFFICIAL_VISION_MODEL_NAME;

    const tagList = ComplexionTypes.TYPES.join('、');
    const systemPrompt =
      '你是精通古籍面诊养生文化的观察助手，参照《黄帝内经·灵枢·五色》《望诊遵经》的观象用语，' +
      '对面部各区域做客观、具体的外观描述（文化娱乐参考，严禁医疗诊断、治疗、用药表述）。\n' +
      '分区要求：\n' +
      '- overallComplexion：整体面色，matchTags 封闭词表内选词\n' +
      '- forehead：上庭·天庭额部，25-45字，含色泽、明润、纹理等\n' +
      '- leftCheek / rightCheek：中庭·左颧颊 / 右颧颊，各25-45字\n' +
      '- eyeArea：目眶双眸，25-40字\n' +
      '- nose：鼻柱准头，20-35字\n' +
      '- lipArea：口唇唇珠，15-30字\n' +
      '- chin：下庭·地阁颏部，20-35字\n' +
      '- details：2-4条细察补充，每条15-30字\n' +
      `overallComplexion 与 matchTags 只能从以下词选择：${tagList}。\n` +
      '只输出一个 JSON 对象，不要 markdown。字段：' +
      'overallComplexion, forehead, leftCheek, rightCheek, nose, chin, eyeArea, lipArea, ' +
      'details(字符串数组), confidence(0-1), averageBrightness(0-255), matchTags(字符串数组)。\n' +
      '描述示例（风格参考，勿照抄）：' +
      'forehead="天庭额部明润尚匀，色象偏黄而不过滞，横纹不显，光泽尚可"; ' +
      'leftCheek="左颧颊色泽匀净，略现红润，未见明显晦暗"; ' +
      'eyeArea="目眶尚清，下睑略有暗影，双眸神彩平常"; ' +
      'chin="地阁颏部轮廓尚丰，色泽与面中相称"。';

    const systemMessage = new VisionSystemMessage();
    systemMessage.role = 'system';
    systemMessage.content = systemPrompt;

    const textPart = new VisionContentTextPart();
    textPart.text =
      '请细察此面部照片：按上庭（天庭额）、中庭（两颧颊）、五官（目鼻唇）、下庭（地阁颏）分区描述，' +
      '用语参照古籍观象，输出 JSON（非医疗，仅文化自测）。';

    const imagePart = new VisionContentImagePart();
    imagePart.image_url.url = imageUrl;

    const userMessage = new VisionChatMessage();
    userMessage.role = 'user';
    // 通义 VL：先 text 后 image_url
    userMessage.content = [textPart, imagePart];

    const payload = new VisionChatPayload();
    payload.model = visionModel;
    payload.messages = [systemMessage, userMessage];
    payload.temperature = 0.2;

    const requestUrl = ApiEndpointUtil.normalizeChatCompletionsEndpoint(config.apiEndpoint);
    console.info(`[CloudVisionService] 请求 model=${visionModel} url=${requestUrl}`);

    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${CloudVisionService.resolveAuthToken(config)}`
    };

    const response = await HttpUtil.post(
      requestUrl,
      JSON.stringify(payload),
      headers,
      45000
    );

    if (!response.ok) {
      const snippet = CloudVisionService.bodySnippet(response.body);
      console.error(`[CloudVisionService] HTTP ${response.statusCode}: ${snippet}`);
      throw new Error(`云端视觉 API 失败 HTTP ${response.statusCode}: ${snippet}`);
    }

    const rawContent = CloudVisionService.extractAssistantContent(response.body);
    if (rawContent.length === 0) {
      const snippet = CloudVisionService.bodySnippet(response.body);
      console.error(`[CloudVisionService] 空内容响应: ${snippet}`);
      throw new Error('云端视觉 API 返回空内容');
    }

    console.info(`[CloudVisionService] 模型回复长度=${rawContent.length}`);
    const feature = CloudVisionService.parseFeatureJson(rawContent);
    feature.analysisEngine = 'cloud_vision';
    return this.sanitizeFeature(feature);
  }

  private static resolveAuthToken(config: ModelConfig): string {
    if (config.modelType === ModelType.PRIVATE) {
      return config.privateToken;
    }
    return config.apiKey;
  }

  /** 从模型回复中提取 JSON */
  private static parseFeatureJson(raw: string): FaceAppearanceFeature {
    let jsonText = raw.trim();
    if (jsonText.startsWith('```')) {
      const start = jsonText.indexOf('{');
      const end = jsonText.lastIndexOf('}');
      if (start >= 0 && end > start) {
        jsonText = jsonText.substring(start, end + 1);
      }
    } else if (!jsonText.startsWith('{')) {
      // 模型可能在 JSON 前后加了说明文字
      const start = jsonText.indexOf('{');
      const end = jsonText.lastIndexOf('}');
      if (start >= 0 && end > start) {
        jsonText = jsonText.substring(start, end + 1);
      }
    }

    let parsed: CloudVisionJson;
    try {
      parsed = JSON.parse(jsonText) as CloudVisionJson;
    } catch (_err) {
      throw new Error('云端视觉返回无法解析为 JSON');
    }

    return {
      overallComplexion: parsed.overallComplexion ?? '气色尚可',
      forehead: parsed.forehead ?? '天庭额部明润尚匀，色泽均匀，未见显著晦暗',
      leftCheek: parsed.leftCheek ?? '左颧颊色泽匀净，气色尚可，未见明显枯槁',
      rightCheek: parsed.rightCheek ?? '右颧颊色泽匀净，气色尚可，与左颊相称',
      nose: parsed.nose ?? '鼻柱准头色泽自然，未见显著红赤或青暗',
      chin: parsed.chin ?? '地阁颏部轮廓尚清，色泽与面中相称',
      eyeArea: parsed.eyeArea ?? '目眶尚清，双眸神彩平常，下睑略有暗影',
      lipArea: parsed.lipArea ?? '口唇唇色自然，唇线尚清',
      details: parsed.details ?? ['整体明润度尚可，为古人观色之常象'],
      confidence: ImageBrightnessUtil.normalize(parsed.confidence, 0.75),
      averageBrightness: ImageBrightnessUtil.normalize(parsed.averageBrightness, 128),
      matchTags: parsed.matchTags ?? ['气色尚可'],
      analysisEngine: 'cloud_vision'
    };
  }

  /** 敏感词过滤 + 封闭词表校正 */
  private sanitizeFeature(input: FaceAppearanceFeature): FaceAppearanceFeature {
    const out: FaceAppearanceFeature = {
      overallComplexion: this.compliance.filterSensitiveWords(input.overallComplexion),
      forehead: this.compliance.filterSensitiveWords(input.forehead),
      leftCheek: this.compliance.filterSensitiveWords(input.leftCheek),
      rightCheek: this.compliance.filterSensitiveWords(input.rightCheek),
      nose: this.compliance.filterSensitiveWords(input.nose),
      chin: this.compliance.filterSensitiveWords(input.chin),
      eyeArea: this.compliance.filterSensitiveWords(input.eyeArea),
      lipArea: this.compliance.filterSensitiveWords(input.lipArea),
      details: [],
      confidence: input.confidence,
      averageBrightness: input.averageBrightness,
      matchTags: CloudVisionService.normalizeTags(input.matchTags, input.overallComplexion),
      analysisEngine: input.analysisEngine
    };
    for (const d of input.details) {
      out.details.push(this.compliance.filterSensitiveWords(d));
    }
    return out;
  }

  /** 将 matchTags 限制在封闭词表内 */
  private static normalizeTags(tags: string[], overall: string): string[] {
    const allowed = ComplexionTypes.TYPES;
    const result: string[] = [];
    for (const t of tags) {
      if (allowed.indexOf(t) >= 0 && result.indexOf(t) < 0) {
        result.push(t);
      }
    }
    if (allowed.indexOf(overall) >= 0 && result.indexOf(overall) < 0) {
      result.unshift(overall);
    }
    if (result.length === 0) {
      result.push('气色尚可');
    }
    return result;
  }

  /** 从 Chat Completions 响应中提取 assistant 文本（兼容 string / 数组 content） */
  private static extractAssistantContent(body: string): string {
    try {
      const parsed = JSON.parse(body) as VisionChatResponse;
      const content = parsed.choices?.[0]?.message?.content;
      if (typeof content === 'string' && content.length > 0) {
        return content;
      }
    } catch (_err) {
      // 继续尝试宽松解析
    }
    return CloudVisionService.extractContentLoose(body);
  }

  /** 宽松解析 content 字段（部分 VL 模型返回 content 数组） */
  private static extractContentLoose(body: string): string {
    try {
      const root = JSON.parse(body) as Record<string, Object>;
      const choicesObj = root['choices'];
      if (!Array.isArray(choicesObj) || choicesObj.length === 0) {
        return '';
      }
      const firstChoice = choicesObj[0] as Record<string, Object>;
      const messageObj = firstChoice['message'] as Record<string, Object>;
      if (messageObj === undefined) {
        return '';
      }
      const contentVal = messageObj['content'];
      if (typeof contentVal === 'string') {
        return contentVal;
      }
      if (Array.isArray(contentVal)) {
        let merged = '';
        for (let i = 0; i < contentVal.length; i++) {
          const part = contentVal[i] as Record<string, Object>;
          const textVal = part['text'];
          if (typeof textVal === 'string') {
            merged += textVal;
          }
        }
        return merged;
      }
    } catch (_err) {
      return '';
    }
    return '';
  }

  /** 截断响应体用于日志/错误提示 */
  private static bodySnippet(body: string): string {
    if (body.length === 0) {
      return '(empty body)';
    }
    return body.length > 240 ? `${body.substring(0, 240)}...` : body;
  }
}
