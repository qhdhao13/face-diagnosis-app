/**
 * 连拍选帧：端上评估清晰度与亮度，从多帧中选出最优 1 张上传
 * 阶段 1：仅选帧，不做多帧 Lab 融合
 */
import { image } from '@kit.ImageKit';
import { CapturedImage } from '../types/AppTypes';
import { LIGHT_BLOCK_THRESHOLD, LIGHT_WARN_THRESHOLD } from './ImageBrightnessUtil';

/** 单帧质量指标（内部使用） */
interface FrameMetrics {
  captured: CapturedImage;
  sharpness: number;
  brightness: number;
  composite: number;
}

/** 解码后用于打分的 RGBA 采样缓冲 */
interface RgbaSample {
  pixels: Uint8Array;
  width: number;
  height: number;
}

/** 连拍默认张数 */
export const BURST_CAPTURE_COUNT: number = 6;

/** 连拍间隔（毫秒），给自动对焦留时间 */
export const BURST_CAPTURE_INTERVAL_MS: number = 180;

/** 打分用缩略图最大宽（降低解码与 Laplacian 开销） */
const SCORE_MAX_WIDTH: number = 480;

/** 解码目标尺寸（与 ImageBase64Util 写法一致） */
class ScorePixelSize {
  width: number = 0;
  height: number = 0;
}

export class FrameQualityUtil {
  /**
   * 从连拍结果中选出综合质量最高的一帧
   * 若全部过暗则返回相对最亮的一帧，由后续亮度拦截再提示用户
   */
  static async selectBest(frames: CapturedImage[]): Promise<CapturedImage | null> {
    if (frames.length === 0) {
      return null;
    }
    if (frames.length === 1) {
      return frames[0];
    }

    const metricsList: FrameMetrics[] = [];
    for (let i = 0; i < frames.length; i++) {
      const item = await FrameQualityUtil.buildMetrics(frames[i]);
      metricsList.push(item);
    }

    // 在批次内归一化清晰度，避免不同设备绝对值差异
    let maxSharp = 0;
    for (let i = 0; i < metricsList.length; i++) {
      if (metricsList[i].sharpness > maxSharp) {
        maxSharp = metricsList[i].sharpness;
      }
    }
    if (maxSharp <= 0) {
      maxSharp = 1;
    }

    for (let i = 0; i < metricsList.length; i++) {
      const m = metricsList[i];
      const normSharp = m.sharpness / maxSharp;
      m.composite = FrameQualityUtil.calcComposite(normSharp, m.brightness);
    }

    let bestIndex = 0;
    for (let i = 1; i < metricsList.length; i++) {
      if (metricsList[i].composite > metricsList[bestIndex].composite) {
        bestIndex = i;
      }
    }

    const best = metricsList[bestIndex];
    console.info(
      `[FrameQualityUtil] 选帧 ${bestIndex + 1}/${frames.length} ` +
      `sharp=${best.sharpness.toFixed(1)} bright=${best.brightness.toFixed(1)} ` +
      `score=${best.composite.toFixed(3)}`
    );
    return best.captured;
  }

  /** 构建单帧指标 */
  private static async buildMetrics(captured: CapturedImage): Promise<FrameMetrics> {
    const sample = await FrameQualityUtil.decodeSample(captured);
    if (sample === null) {
      return {
        captured: captured,
        sharpness: 0,
        brightness: 0,
        composite: 0
      };
    }
    const brightness = FrameQualityUtil.measureBrightness(sample);
    const sharpness = FrameQualityUtil.measureSharpness(sample);
    return {
      captured: captured,
      sharpness: sharpness,
      brightness: brightness,
      composite: 0
    };
  }

  /**
   * 综合分：清晰度 70% + 亮度适宜度 30%
   * 过暗帧大幅降权，避免选中模糊但偶然较亮的废片
   */
  private static calcComposite(normSharpness: number, brightness: number): number {
    const brightScore = FrameQualityUtil.brightnessFitness(brightness);
    let penalty = 1.0;
    if (brightness < LIGHT_BLOCK_THRESHOLD) {
      penalty = 0.15;
    } else if (brightness < LIGHT_WARN_THRESHOLD) {
      penalty = 0.55;
    }
    return (normSharpness * 0.7 + brightScore * 0.3) * penalty;
  }

  /** 亮度适宜度：80~180 最佳，过暗/过曝降分 */
  private static brightnessFitness(brightness: number): number {
    if (brightness < LIGHT_BLOCK_THRESHOLD) {
      return 0.05;
    }
    if (brightness < LIGHT_WARN_THRESHOLD) {
      return 0.35;
    }
    if (brightness > 235) {
      return 0.25;
    }
    if (brightness > 210) {
      return 0.6;
    }
    const ideal = 128;
    const diff = Math.abs(brightness - ideal);
    return Math.max(0.2, 1.0 - diff / 128);
  }

  /** JPEG → 缩略 RGBA */
  private static async decodeSample(captured: CapturedImage): Promise<RgbaSample | null> {
    if (captured.data.byteLength === 0) {
      return null;
    }
    try {
      const imageSource = image.createImageSource(captured.data);
      const srcInfo = await imageSource.getImageInfo();
      let targetW = srcInfo.size.width;
      let targetH = srcInfo.size.height;
      const maxDim = Math.max(targetW, targetH);
      if (maxDim > SCORE_MAX_WIDTH) {
        const ratio = SCORE_MAX_WIDTH / maxDim;
        targetW = Math.round(targetW * ratio);
        targetH = Math.round(targetH * ratio);
      }
      const desiredSize = new ScorePixelSize();
      desiredSize.width = targetW;
      desiredSize.height = targetH;
      const decodeOpts: image.DecodingOptions = {
        editable: true,
        desiredSize: desiredSize
      };
      const pixelMap = await imageSource.createPixelMap(decodeOpts);
      const info = await pixelMap.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      if (width === 0 || height === 0) {
        pixelMap.release();
        imageSource.release();
        return null;
      }
      const buffer = new ArrayBuffer(width * height * 4);
      await pixelMap.readPixelsToBuffer(buffer);
      pixelMap.release();
      imageSource.release();
      return {
        pixels: new Uint8Array(buffer),
        width: width,
        height: height
      };
    } catch (err) {
      console.error('[FrameQualityUtil] 解码失败', JSON.stringify(err));
      return null;
    }
  }

  /** 画面中央 70% 区域平均亮度 */
  private static measureBrightness(sample: RgbaSample): number {
    const marginX = Math.floor(sample.width * 0.15);
    const marginY = Math.floor(sample.height * 0.15);
    const x0 = marginX;
    const x1 = sample.width - marginX;
    const y0 = marginY;
    const y1 = sample.height - marginY;
    let sum = 0;
    let count = 0;
    const step = 3;

    for (let y = y0; y < y1; y += step) {
      for (let x = x0; x < x1; x += step) {
        const idx = (y * sample.width + x) * 4;
        if (idx + 2 >= sample.pixels.length) {
          continue;
        }
        const r = sample.pixels[idx];
        const g = sample.pixels[idx + 1];
        const b = sample.pixels[idx + 2];
        if (r > 250 && g > 250 && b > 250) {
          continue;
        }
        sum += 0.299 * r + 0.587 * g + 0.114 * b;
        count++;
      }
    }
    return count === 0 ? 128 : sum / count;
  }

  /**
   * 中心区域 Laplacian 方差（越大越清晰）
   * 在缩略图上采样，步长 2 兼顾速度与稳定性
   */
  private static measureSharpness(sample: RgbaSample): number {
    const w = sample.width;
    const h = sample.height;
    const marginX = Math.floor(w * 0.2);
    const marginY = Math.floor(h * 0.2);
    const x0 = marginX;
    const x1 = w - marginX;
    const y0 = marginY;
    const y1 = h - marginY;

    if (x1 - x0 < 8 || y1 - y0 < 8) {
      return 0;
    }

    const gray = new Float32Array(w * h);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        const idx = (y * w + x) * 4;
        gray[y * w + x] = 0.299 * sample.pixels[idx] + 0.587 * sample.pixels[idx + 1] +
          0.114 * sample.pixels[idx + 2];
      }
    }

    let lapSum = 0;
    let lapSqSum = 0;
    let count = 0;
    const step = 2;

    for (let y = y0 + 1; y < y1 - 1; y += step) {
      for (let x = x0 + 1; x < x1 - 1; x += step) {
        const c = gray[y * w + x];
        const lap = 4 * c - gray[y * w + (x - 1)] - gray[y * w + (x + 1)] -
          gray[(y - 1) * w + x] - gray[(y + 1) * w + x];
        lapSum += lap;
        lapSqSum += lap * lap;
        count++;
      }
    }

    if (count === 0) {
      return 0;
    }
    const mean = lapSum / count;
    const variance = lapSqSum / count - mean * mean;
    return Math.max(0, variance);
  }
}
