/**
 * 视觉模型输入预处理
 * JPEG/RGBA → Float32 NHWC tensor（MindSpore 常用格式）
 */
import { image } from '@kit.ImageKit';
import { CapturedImage } from '../../common/types/AppTypes';
import { OmModelInputConfig, OmTensorLayout } from './OmModelTypes';

export class VisionImagePreprocessor {
  /**
   * 将拍照图像转为模型输入 Float32Array
   * @param captured 相机 JPEG 或 RGBA
   * @param config 模型输入宽高与归一化参数
   */
  static async toFloat32Input(captured: CapturedImage, config: OmModelInputConfig): Promise<Float32Array | null> {
    try {
      const rgba = await VisionImagePreprocessor.ensureRgba(captured);
      if (rgba.width === 0 || rgba.data.byteLength === 0) {
        return null;
      }
      const layout = config.dataFormat ?? 'NHWC';
      return VisionImagePreprocessor.resizeAndNormalize(
        rgba.data,
        rgba.width,
        rgba.height,
        config.inputWidth,
        config.inputHeight,
        config,
        layout
      );
    } catch (err) {
      console.error('[VisionImagePreprocessor] 预处理失败', JSON.stringify(err));
      return null;
    }
  }

  /** JPEG 解码为 RGBA */
  private static async ensureRgba(captured: CapturedImage): Promise<CapturedImage> {
    if (captured.format === 'rgba' && captured.width > 0) {
      return captured;
    }
    const imageSource = image.createImageSource(captured.data);
    try {
      const pixelMap = await imageSource.createPixelMap({ editable: true });
      const info = await pixelMap.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      const buffer = new ArrayBuffer(width * height * 4);
      await pixelMap.readPixelsToBuffer(buffer);
      pixelMap.release();
      return { data: buffer, width: width, height: height, format: 'rgba' };
    } finally {
      imageSource.release();
    }
  }

  /** 双线性采样缩放到目标尺寸并归一化 */
  private static resizeAndNormalize(
    rgbaBuffer: ArrayBuffer,
    srcW: number,
    srcH: number,
    dstW: number,
    dstH: number,
    config: OmModelInputConfig,
    layout: OmTensorLayout
  ): Float32Array {
    const src = new Uint8Array(rgbaBuffer);
    const out = new Float32Array(dstW * dstH * 3);

    for (let y = 0; y < dstH; y++) {
      const srcY = Math.min(srcH - 1, Math.floor(y * srcH / dstH));
      for (let x = 0; x < dstW; x++) {
        const srcX = Math.min(srcW - 1, Math.floor(x * srcW / dstW));
        const srcIdx = (srcY * srcW + srcX) * 4;
        const r = (src[srcIdx] - config.meanR) * config.scale;
        const g = (src[srcIdx + 1] - config.meanG) * config.scale;
        const b = (src[srcIdx + 2] - config.meanB) * config.scale;

        if (layout === 'NCHW') {
          // NCHW：按通道平面排列，匹配 UltraFace / 多数 ONNX 人脸模型
          out[0 * dstH * dstW + y * dstW + x] = r;
          out[1 * dstH * dstW + y * dstW + x] = g;
          out[2 * dstH * dstW + y * dstW + x] = b;
        } else {
          // NHWC：按像素交错排列
          const pixelIdx = (y * dstW + x) * 3;
          out[pixelIdx] = r;
          out[pixelIdx + 1] = g;
          out[pixelIdx + 2] = b;
        }
      }
    }
    return out;
  }

  /** Float32Array → ArrayBuffer（供 MSTensor.setData） */
  static float32ToBuffer(data: Float32Array): ArrayBuffer {
    const buffer = new ArrayBuffer(data.byteLength);
    new Float32Array(buffer).set(data);
    return buffer;
  }
}
