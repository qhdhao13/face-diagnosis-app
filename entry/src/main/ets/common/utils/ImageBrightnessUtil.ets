/**
 * 本地图像亮度测量（不依赖 AI 返回值）
 * 用于拍照光线判定，避免云端模型 confidence/brightness 误报
 */
import { image } from '@kit.ImageKit';
import { CapturedImage } from '../types/AppTypes';

/** 低于此值才拦截拍照（0-255，约等于很暗的环境） */
export const LIGHT_BLOCK_THRESHOLD: number = 28;

/** 低于此值仅 UI 提示，不拦截 */
export const LIGHT_WARN_THRESHOLD: number = 45;

export class ImageBrightnessUtil {
  /**
   * 从 JPEG 解码并采样画面中心区域，计算平均亮度 0-255
   */
  static async measure(captured: CapturedImage): Promise<number> {
    if (captured.data.byteLength === 0) {
      return 0;
    }
    try {
      const imageSource = image.createImageSource(captured.data);
      const pixelMap = await imageSource.createPixelMap({ editable: true });
      const info = await pixelMap.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      if (width === 0 || height === 0) {
        pixelMap.release();
        imageSource.release();
        return 0;
      }
      const buffer = new ArrayBuffer(width * height * 4);
      await pixelMap.readPixelsToBuffer(buffer);
      pixelMap.release();
      imageSource.release();
      return ImageBrightnessUtil.sampleCenterBrightness(new Uint8Array(buffer), width, height);
    } catch (err) {
      console.error('[ImageBrightnessUtil] 亮度测量失败', JSON.stringify(err));
      return 128;
    }
  }

  /**
   * 规范化 AI 返回的亮度（部分模型返回 0-1 小数）
   */
  static normalize(value: number | undefined, fallback: number = 128): number {
    if (value === undefined || Number.isNaN(value)) {
      return fallback;
    }
    let brightness = value;
    if (brightness > 0 && brightness <= 1) {
      brightness = brightness * 255;
    }
    return Math.max(0, Math.min(255, Math.round(brightness)));
  }

  /** 采样画面中央 70% 区域，跳过过曝像素 */
  private static sampleCenterBrightness(pixels: Uint8Array, width: number, height: number): number {
    const marginX = Math.floor(width * 0.15);
    const marginY = Math.floor(height * 0.15);
    const x0 = marginX;
    const x1 = width - marginX;
    const y0 = marginY;
    const y1 = height - marginY;
    let sumR = 0;
    let sumG = 0;
    let sumB = 0;
    let count = 0;
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
      return 128;
    }
    const avgR = sumR / count;
    const avgG = sumG / count;
    const avgB = sumB / count;
    return 0.299 * avgR + 0.587 * avgG + 0.114 * avgB;
  }
}
