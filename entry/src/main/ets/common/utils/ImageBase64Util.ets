/**
 * 图像 Base64 编码工具（供云端视觉 API 上传）
 * 上传前压缩 JPEG，避免原图过大导致 API 超时或 400
 */
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
import { CapturedImage } from '../types/AppTypes';

/** 云端上传最长边像素（控制请求体体积） */
const CLOUD_MAX_SIDE_PX: number = 960;
/** JPEG 压缩质量 0-100 */
const CLOUD_JPEG_QUALITY: number = 80;

/** JPEG 压缩目标尺寸 */
class PixelSize {
  width: number = 0;
  height: number = 0;
}

export class ImageBase64Util {
  /** 将拍照结果转为 JPEG Base64 字符串（不含 data: 前缀） */
  static async toJpegBase64(captured: CapturedImage): Promise<string> {
    const jpegBuffer = await ImageBase64Util.toCompressedJpeg(captured);
    const helper = new util.Base64Helper();
    const base64 = await helper.encodeToString(new Uint8Array(jpegBuffer));
    console.info(`[ImageBase64Util] base64Len=${base64.length} jpegBytes=${jpegBuffer.byteLength}`);
    return base64;
  }

  /** 解码并压缩为适合云端上传的 JPEG */
  private static async toCompressedJpeg(captured: CapturedImage): Promise<ArrayBuffer> {
    const imageSource = image.createImageSource(captured.data);
    try {
      const srcInfo = await imageSource.getImageInfo();
      let targetW = srcInfo.size.width;
      let targetH = srcInfo.size.height;
      const maxDim = Math.max(targetW, targetH);

      if (maxDim > CLOUD_MAX_SIDE_PX) {
        const ratio = CLOUD_MAX_SIDE_PX / maxDim;
        targetW = Math.round(targetW * ratio);
        targetH = Math.round(targetH * ratio);
      }

      const desiredSize = new PixelSize();
      desiredSize.width = targetW;
      desiredSize.height = targetH;
      const decodeOpts: image.DecodingOptions = {
        editable: true,
        desiredSize: desiredSize
      };
      const pixelMap = await imageSource.createPixelMap(decodeOpts);
      const packer = image.createImagePacker();
      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: CLOUD_JPEG_QUALITY
      };
      try {
        const buffer = await packer.packToData(pixelMap, packOpts);
        return buffer;
      } catch (packErr) {
        console.error('[ImageBase64Util] JPEG 压缩失败', JSON.stringify(packErr));
        throw new Error('图像压缩失败');
      } finally {
        pixelMap.release();
        packer.release();
      }
    } catch (err) {
      console.error('[ImageBase64Util] 图像处理失败', JSON.stringify(err));
      throw new Error('图像处理失败');
    } finally {
      imageSource.release();
    }
  }
}
