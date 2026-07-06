/**
 * 离线肤色/亮度分析器
 * 不依赖深度学习模型，基于 RGB 分区统计 + 规则映射
 * 支持动态人脸框分区，供规则管线与 .om 混合管线共用
 */
import { image } from '@kit.ImageKit';
import { CapturedImage, FaceAppearanceFeature, FaceBoundingBox, FaceRegionRect } from '../../common/types/AppTypes';
import { ComplexionTagMapper } from './ComplexionTagMapper';
import { FaceRegionLayout } from './FaceRegionLayout';

/** 单个面部分区的颜色统计 */
interface RegionStats {
  avgR: number;
  avgG: number;
  avgB: number;
  brightness: number;
  saturation: number;
  sampleCount: number;
}

export class ImageColorAnalyzer {
  /**
   * 分析拍照图像（可选人脸框，自动生成分区）
   * @param captured 内存图像
   * @param faceBox 人脸检测框，缺省使用居中默认框
   */
  async analyze(captured: CapturedImage, faceBox?: FaceBoundingBox): Promise<FaceAppearanceFeature> {
    const regions = FaceRegionLayout.buildRegions(faceBox);
    const globalRegion = FaceRegionLayout.buildGlobalRegion(faceBox);
    return this.analyzeWithRegions(captured, regions, globalRegion);
  }

  /**
   * 按指定分区列表分析（.om 管线 Stage2 输出分区时使用）
   */
  async analyzeWithRegions(
    captured: CapturedImage,
    regions: FaceRegionRect[],
    globalRegion?: FaceRegionRect
  ): Promise<FaceAppearanceFeature> {
    const rgba = await this.ensureRgba(captured);
    if (rgba.data.byteLength === 0 || rgba.width === 0) {
      return ImageColorAnalyzer.buildFallback('图像数据无效');
    }

    const global = globalRegion ?? FaceRegionLayout.buildGlobalRegion(undefined);
    const regionMap: Map<string, RegionStats> = new Map();

    for (const region of regions) {
      const stats = this.sampleRegion(rgba.data, rgba.width, rgba.height, region);
      regionMap.set(region.name, stats);
    }

    const globalStats = this.sampleRegion(rgba.data, rgba.width, rgba.height, global);

    if (globalStats.brightness < 28) {
      return ImageColorAnalyzer.buildFallback('光线不足，请在明亮环境下重拍', globalStats.brightness);
    }

    const overallComplexion = ComplexionTagMapper.mapFromColorStats(
      globalStats.avgR, globalStats.avgG, globalStats.avgB,
      globalStats.brightness, globalStats.saturation
    );
    const forehead = ImageColorAnalyzer.describeRegion('额头', regionMap.get('额头') ?? globalStats);
    const leftCheek = ImageColorAnalyzer.describeRegion('左脸颊', regionMap.get('左脸颊') ?? globalStats);
    const rightCheek = ImageColorAnalyzer.describeRegion('右脸颊', regionMap.get('右脸颊') ?? globalStats);
    const nose = ImageColorAnalyzer.describeRegion('鼻部', regionMap.get('鼻部') ?? globalStats);
    const chin = ImageColorAnalyzer.describeRegion('下巴', regionMap.get('下巴') ?? globalStats);
    const eyeArea = ImageColorAnalyzer.describeRegion('眼周', regionMap.get('眼周') ?? globalStats);
    const lipArea = ImageColorAnalyzer.describeLip(regionMap.get('唇部') ?? globalStats);

    const details = ImageColorAnalyzer.collectDetails(regionMap, globalStats);
    const matchTags = ImageColorAnalyzer.buildMatchTags(
      overallComplexion, forehead, leftCheek, rightCheek, nose, chin, eyeArea, lipArea, details
    );

    const confidence = ImageColorAnalyzer.calcConfidence(globalStats, regionMap);

    return {
      overallComplexion: overallComplexion,
      forehead: forehead,
      leftCheek: leftCheek,
      rightCheek: rightCheek,
      nose: nose,
      chin: chin,
      eyeArea: eyeArea,
      lipArea: lipArea,
      details: details,
      confidence: confidence,
      averageBrightness: globalStats.brightness,
      matchTags: matchTags
    };
  }

  /** 将 JPEG 解码为 RGBA 像素 */
  private async ensureRgba(captured: CapturedImage): Promise<CapturedImage> {
    if (captured.format === 'rgba') {
      return captured;
    }
    try {
      const imageSource = image.createImageSource(captured.data);
      const pixelMap = await imageSource.createPixelMap({ editable: true });
      const info = await pixelMap.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      const buffer = new ArrayBuffer(width * height * 4);
      await pixelMap.readPixelsToBuffer(buffer);
      pixelMap.release();
      imageSource.release();
      return { data: buffer, width: width, height: height, format: 'rgba' };
    } catch (err) {
      console.error('[ImageColorAnalyzer] JPEG解码失败', JSON.stringify(err));
      return { data: new ArrayBuffer(0), width: 0, height: 0, format: 'rgba' };
    }
  }

  /** 在指定区域内采样像素并统计 RGB */
  private sampleRegion(
    buffer: ArrayBuffer,
    width: number,
    height: number,
    rect: FaceRegionRect
  ): RegionStats {
    const pixels = new Uint8Array(buffer);
    let sumR = 0;
    let sumG = 0;
    let sumB = 0;
    let count = 0;

    const x0 = Math.floor(rect.xStart * width);
    const x1 = Math.floor(rect.xEnd * width);
    const y0 = Math.floor(rect.yStart * height);
    const y1 = Math.floor(rect.yEnd * height);

    const step = 4;
    for (let y = y0; y < y1; y += step) {
      for (let x = x0; x < x1; x += step) {
        const idx = (y * width + x) * 4;
        if (idx + 2 >= pixels.length) {
          continue;
        }
        const r = pixels[idx];
        const g = pixels[idx + 1];
        const b = pixels[idx + 2];
        if (r > 250 && g > 250 && b > 250) {
          continue;
        }
        sumR += r;
        sumG += g;
        sumB += b;
        count++;
      }
    }

    if (count === 0) {
      return { avgR: 128, avgG: 128, avgB: 128, brightness: 128, saturation: 0, sampleCount: 0 };
    }

    const avgR = sumR / count;
    const avgG = sumG / count;
    const avgB = sumB / count;
    const brightness = 0.299 * avgR + 0.587 * avgG + 0.114 * avgB;
    const maxC = Math.max(avgR, avgG, avgB);
    const minC = Math.min(avgR, avgG, avgB);
    const saturation = maxC === 0 ? 0 : (maxC - minC) / maxC;

    return {
      avgR: avgR, avgG: avgG, avgB: avgB,
      brightness: brightness, saturation: saturation, sampleCount: count
    };
  }

  /** 描述单个分区状态（古籍观象用语） */
  private static describeRegion(name: string, stats: RegionStats): string {
    const complexion = ComplexionTagMapper.mapFromColorStats(
      stats.avgR, stats.avgG, stats.avgB, stats.brightness, stats.saturation
    );
    let texture = '色泽匀净';
    let gloss = '明润度尚可';
    if (stats.saturation > 0.35 && stats.avgR > stats.avgG + 15) {
      texture = '略现红润';
      gloss = '光泽偏活';
    } else if (stats.brightness < 100) {
      texture = '略偏晦暗';
      gloss = '明润不足';
    } else if (stats.saturation < 0.12 && stats.brightness > 160) {
      texture = '肌理细腻';
      gloss = '明润偏清';
    } else if (stats.sampleCount > 0 && stats.saturation > 0.25) {
      texture = '气色尚活';
    }

    if (name === '额头') {
      return `天庭额部见${complexion}之象，${texture}，${gloss}，横纹不显`;
    }
    if (name === '左脸颊') {
      return `左颧颊见${complexion}之象，${texture}，与面中色泽相称`;
    }
    if (name === '右脸颊') {
      return `右颧颊见${complexion}之象，${texture}，与左颊尚匀`;
    }
    if (name === '鼻部') {
      return `鼻柱准头见${complexion}之象，${texture}，未见显著赤滞`;
    }
    if (name === '下巴') {
      return `地阁颏部见${complexion}之象，轮廓尚清，${gloss}`;
    }
    if (name === '眼周') {
      return `目眶尚清，见${complexion}之象，下睑${texture}，神彩平常`;
    }
    return `${name}见${complexion}之象，${texture}，${gloss}`;
  }

  /** 唇区专用描述（古籍称唇珠） */
  private static describeLip(stats: RegionStats): string {
    if (stats.avgR > stats.avgG + 25 && stats.brightness > 100) {
      return '口唇唇珠红润，唇线尚清，为古人观唇之常象';
    }
    if (stats.brightness < 110 && stats.saturation < 0.2) {
      return '口唇色偏淡，唇线尚清，明润度略欠';
    }
    if (stats.avgR > 140 && stats.saturation > 0.3) {
      return '口唇色略深，唇线清晰，未见干裂之象';
    }
    return '口唇唇色自然，唇珠尚润，唇线分明';
  }

  /** 收集细节特征标签 */
  private static collectDetails(regionMap: Map<string, RegionStats>, global: RegionStats): string[] {
    const details: string[] = [];
    const left = regionMap.get('左脸颊');
    const right = regionMap.get('右脸颊');
    const eye = regionMap.get('眼周');

    if (left !== undefined && right !== undefined) {
      if (Math.abs(left.avgR - right.avgR) > 20 || Math.abs(left.brightness - right.brightness) > 25) {
        details.push('两颧颊色泽略有参差，宜观整体明润是否匀净');
      }
    }
    if (eye !== undefined && eye.brightness < global.brightness - 20) {
      details.push('目下略暗，古人称「阙」处宜早寝养精');
    }
    if (global.saturation > 0.3 && global.avgR > global.avgG + 10) {
      details.push('面中略现红润，宜清淡饮食、情志平和');
    }
    if (global.brightness > 150 && global.saturation < 0.15) {
      details.push('整体明润偏清，属《灵枢·五色》所称常象之一');
    }
    if (global.brightness < 90) {
      details.push('整体明度偏低，宜择明亮处再观');
    }
    if (details.length === 0) {
      details.push('五部分区色泽尚匀，整体为古人观色之常象');
    }
    return details;
  }

  /** 构建结构化匹配标签 */
  private static buildMatchTags(
    overall: string,
    forehead: string,
    leftCheek: string,
    rightCheek: string,
    nose: string,
    chin: string,
    eyeArea: string,
    lipArea: string,
    details: string[]
  ): string[] {
    return [
      overall, forehead, leftCheek, rightCheek,
      nose, chin, eyeArea, lipArea, ...details
    ];
  }

  /** 计算分析置信度（基于亮度与采样数） */
  private static calcConfidence(global: RegionStats, regionMap: Map<string, RegionStats>): number {
    let validRegions = 0;
    regionMap.forEach((s: RegionStats) => {
      if (s.sampleCount > 10) {
        validRegions++;
      }
    });
    const regionScore = regionMap.size > 0 ? validRegions / regionMap.size : 0.5;
    const brightScore = global.brightness >= 60 && global.brightness <= 220 ? 1.0 : 0.5;
    return Math.min(0.95, 0.4 + regionScore * 0.3 + brightScore * 0.25);
  }

  /** 异常情况下的兜底特征 */
  private static buildFallback(reason: string, brightness: number = 0): FaceAppearanceFeature {
    return {
      overallComplexion: '气色尚可',
      forehead: '天庭额部明润尚匀，色泽均匀，未见显著晦暗',
      leftCheek: '左颧颊色泽匀净，气色尚可',
      rightCheek: '右颧颊色泽匀净，气色尚可',
      nose: '鼻柱准头色泽自然，未见显著赤滞',
      chin: '地阁颏部轮廓尚清，色泽与面中相称',
      eyeArea: '目眶尚清，双眸神彩平常',
      lipArea: '口唇唇色自然，唇线尚清',
      details: [reason],
      confidence: brightness < 28 ? 0.2 : 0.5,
      averageBrightness: brightness,
      matchTags: ['通用', '整体气色观察参考', reason]
    };
  }
}
