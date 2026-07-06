/**
 * 体验免 Key 模式：经开发者服务器代理调用 AI（Key 仅存服务端）
 */
import { CapturedImage, FaceAppearanceFeature, Region25ColorItem, Region25SessionResult } from '../common/types/AppTypes';
import { ExperienceServerConfig } from '../common/constants/AppConstants';
import { HttpUtil } from '../common/utils/HttpUtil';
import { ImageBase64Util } from '../common/utils/ImageBase64Util';
import { ImageBrightnessUtil } from '../common/utils/ImageBrightnessUtil';
import { PhoneAuthModule } from '../modules/auth/PhoneAuthModule';

class VisionProxyRequest {
  imageBase64: string = '';
  width: number = 0;
  height: number = 0;
  profileGender?: string;
}

class VisionProxyFeatureBody {
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

class VisionProxyResponse {
  ok?: boolean;
  feature?: VisionProxyFeatureBody;
  dailyFreeRemaining?: number;
  message?: string;
}

class TextProxyRequest {
  systemPrompt: string = '';
  userPrompt: string = '';
}

class TextProxyResponse {
  ok?: boolean;
  content?: string;
  message?: string;
}

class Region25UrlsBody {
  report?: string;
  annotatedImage?: string;
  originalImage?: string;
}

class Region25RegionBody {
  id?: number;
  name?: string;
  dominant_color?: string;
  pathology_hint?: string;
  floating_sinking?: string;
  lustre?: string;
  scatter_cluster?: string;
  interpretation?: string;
  confidence?: number;
}

class Region25SummaryBody {
  summary_text?: string;
  disclaimer?: string;
}

class Region25ColorReportBody {
  line_items?: string[];
  regions?: Region25RegionBody[];
  summary?: Region25SummaryBody;
}

class Region25AnalyzeResponse {
  ok?: boolean;
  sessionId?: string;
  colorReport?: Region25ColorReportBody;
  urls?: Region25UrlsBody;
  genderCheck?: Region25GenderCheckBody;
  meta?: Region25MetaBody;
  dailyFreeRemaining?: number;
  message?: string;
}

class Region25GenderCheckBody {
  mismatch?: boolean;
  warning?: string;
}

class Region25MetaBody {
  detectedGender?: string;
  genderConfidence?: number;
  genderMismatch?: boolean;
  genderWarning?: string;
}

export class ExperienceProxyService {
  private phoneAuth: PhoneAuthModule;

  constructor(phoneAuth: PhoneAuthModule) {
    this.phoneAuth = phoneAuth;
  }

  isServerConfigured(): boolean {
    return ExperienceServerConfig.BASE_URL.length > 0;
  }

  private buildAuthHeaders(): Record<string, string> {
    return {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${this.phoneAuth.getAuthToken()}`
    };
  }

  async analyzeVision(captured: CapturedImage): Promise<FaceAppearanceFeature> {
    const base64 = await ImageBase64Util.toJpegBase64(captured);
    const req = new VisionProxyRequest();
    req.imageBase64 = base64;
    req.width = captured.width;
    req.height = captured.height;

    const url = `${ExperienceServerConfig.BASE_URL}${ExperienceServerConfig.VISION_PATH}`;
    const response = await HttpUtil.post(url, JSON.stringify(req), this.buildAuthHeaders(), 60000);

    if (!response.ok) {
      throw new Error(`体验视觉代理失败 HTTP ${response.statusCode}`);
    }

    let parsed: VisionProxyResponse;
    try {
      parsed = JSON.parse(response.body) as VisionProxyResponse;
    } catch (_err) {
      throw new Error('体验视觉代理返回非 JSON');
    }

    if (parsed.ok !== true || parsed.feature === undefined) {
      throw new Error(parsed.message ?? '体验视觉代理失败');
    }

    if (parsed.dailyFreeRemaining !== undefined) {
      await this.phoneAuth.refreshStatus();
    }

    const f = parsed.feature;
    const feature: FaceAppearanceFeature = {
      overallComplexion: f.overallComplexion ?? '气色尚可',
      forehead: f.forehead ?? '天庭额部明润尚匀',
      leftCheek: f.leftCheek ?? '左颧颊色泽匀净',
      rightCheek: f.rightCheek ?? '右颧颊色泽匀净',
      nose: f.nose ?? '鼻柱准头色泽自然',
      chin: f.chin ?? '地阁颏部轮廓尚清',
      eyeArea: f.eyeArea ?? '目眶尚清',
      lipArea: f.lipArea ?? '口唇唇色自然',
      details: f.details ?? ['体验模式 AI 观察参考'],
      confidence: ImageBrightnessUtil.normalize(f.confidence, 0.75),
      averageBrightness: ImageBrightnessUtil.normalize(f.averageBrightness, 128),
      matchTags: f.matchTags ?? ['气色尚可'],
      analysisEngine: 'experience_proxy'
    };
    return feature;
  }

  /**
   * 25色部 Lab 云端分析（图片与 JSON 存服务器，App 仅接收 URL + 报告）
   */
  async analyzeRegion25(captured: CapturedImage, profileGender?: string): Promise<Region25SessionResult> {
    const base64 = await ImageBase64Util.toJpegBase64(captured);
    const req = new VisionProxyRequest();
    req.imageBase64 = base64;
    req.width = captured.width;
    req.height = captured.height;
    if (profileGender !== undefined && profileGender.length > 0 && profileGender !== '未设置') {
      req.profileGender = profileGender;
    }

    const url = `${ExperienceServerConfig.BASE_URL}${ExperienceServerConfig.REGION25_ANALYZE_PATH}`;
    const response = await HttpUtil.post(url, JSON.stringify(req), this.buildAuthHeaders(), 120000);

    if (!response.ok) {
      throw new Error(`25色部分析失败 HTTP ${response.statusCode}`);
    }

    let parsed: Region25AnalyzeResponse;
    try {
      parsed = JSON.parse(response.body) as Region25AnalyzeResponse;
    } catch (_err) {
      throw new Error('25色部分析返回非 JSON');
    }

    if (parsed.ok !== true || parsed.sessionId === undefined || parsed.colorReport === undefined) {
      throw new Error(parsed.message ?? '25色部分析失败');
    }

    if (parsed.dailyFreeRemaining !== undefined) {
      await this.phoneAuth.refreshStatus();
    }

    const base = ExperienceServerConfig.BASE_URL;
    const report = parsed.colorReport;
    const regions: Region25ColorItem[] = [];
    const rawRegions = report.regions ?? [];
    for (let i = 0; i < rawRegions.length; i++) {
      const r = rawRegions[i];
      regions.push({
        id: r.id ?? i + 1,
        name: r.name ?? '',
        dominantColor: r.dominant_color ?? '',
        pathologyHint: r.pathology_hint ?? '',
        floatingSinking: r.floating_sinking ?? '',
        lustre: r.lustre ?? '',
        scatterCluster: r.scatter_cluster ?? '',
        interpretation: r.interpretation ?? '',
        confidence: ImageBrightnessUtil.normalize(r.confidence, 0.8)
      });
    }

    const annotatedPath = parsed.urls?.annotatedImage ?? '';
    const originalPath = parsed.urls?.originalImage ?? '';
    const reportPath = parsed.urls?.report ?? '';
    const token = this.phoneAuth.getAuthToken();
    const tokenQuery = token.length > 0 ? `?token=${encodeURIComponent(token)}` : '';

    const genderCheck = parsed.genderCheck;
    const meta = parsed.meta;
    const detectedGender = meta?.detectedGender ?? '';
    const genderConfidence = meta?.genderConfidence ?? 0;
    const genderMismatch = genderCheck?.mismatch === true || meta?.genderMismatch === true;
    const genderWarning = genderCheck?.warning ?? meta?.genderWarning ?? '';

    return {
      sessionId: parsed.sessionId,
      annotatedImageUrl: annotatedPath.startsWith('http')
        ? `${annotatedPath}${annotatedPath.includes('?') ? '&' : '?'}token=${encodeURIComponent(token)}`
        : `${base}${annotatedPath}${tokenQuery}`,
      originalImageUrl: originalPath.startsWith('http')
        ? `${originalPath}${originalPath.includes('?') ? '&' : '?'}token=${encodeURIComponent(token)}`
        : `${base}${originalPath}${tokenQuery}`,
      reportUrl: reportPath.startsWith('http') ? reportPath : `${base}${reportPath}`,
      summaryText: report.summary?.summary_text ?? '',
      lineItems: report.line_items ?? [],
      disclaimer: report.summary?.disclaimer ?? '',
      regions: regions,
      detectedGender: detectedGender.length > 0 ? detectedGender : undefined,
      genderConfidence: genderConfidence > 0 ? genderConfidence : undefined,
      genderMismatch: genderMismatch ? true : undefined,
      genderWarning: genderWarning.length > 0 ? genderWarning : undefined
    };
  }

  async generateText(systemPrompt: string, userPrompt: string): Promise<string> {
    const req = new TextProxyRequest();
    req.systemPrompt = systemPrompt;
    req.userPrompt = userPrompt;

    const url = `${ExperienceServerConfig.BASE_URL}${ExperienceServerConfig.TEXT_PATH}`;
    const response = await HttpUtil.post(url, JSON.stringify(req), this.buildAuthHeaders(), 45000);

    if (!response.ok) {
      throw new Error(`体验文案代理失败 HTTP ${response.statusCode}`);
    }

    let parsed: TextProxyResponse;
    try {
      parsed = JSON.parse(response.body) as TextProxyResponse;
    } catch (_err) {
      throw new Error('体验文案代理返回非 JSON');
    }

    if (parsed.ok !== true || parsed.content === undefined || parsed.content.length === 0) {
      throw new Error(parsed.message ?? '体验文案代理返回空内容');
    }
    return parsed.content;
  }
}
