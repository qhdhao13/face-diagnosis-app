/**
 * 按扫描页椭圆对准框，从全景照片中裁切头像区域再上传分析
 */
import { image } from '@kit.ImageKit';
import { CapturedImage } from '../types/AppTypes';

/** 与 ScanPage 椭圆对准框一致的裁切参数 */
export interface FaceGuideCropSpec {
  /** 预览区宽（像素） */
  viewWidthPx: number;
  /** 预览区高（像素） */
  viewHeightPx: number;
  /** 椭圆宽占预览宽比例 */
  ovalWidthRatio: number;
  /** 椭圆宽高比 width/height */
  ovalAspect: number;
  /** 椭圆距预览顶边（像素） */
  ovalTopMarginPx: number;
}

/** 裁切矩形 */
interface CropRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

/** 默认与 ScanPage 一致 */
export const FACE_GUIDE_OVAL_WIDTH_RATIO: number = 0.56;
export const FACE_GUIDE_OVAL_ASPECT: number = 0.68;
export const FACE_GUIDE_OVAL_TOP_MARGIN_VP: number = 44;

/** 裁切输出 JPEG 质量 */
const CROP_JPEG_QUALITY: number = 88;

export class PortraitCropUtil {
  /**
   * 将全景拍照结果裁切为椭圆外接矩形内的头像区域
   * 失败时返回 null，由调用方决定是否使用原图
   */
  static async cropToFaceGuide(
    captured: CapturedImage,
    spec: FaceGuideCropSpec
  ): Promise<CapturedImage | null> {
    if (captured.data.byteLength === 0) {
      return null;
    }
    try {
      const imageSource = image.createImageSource(captured.data);
      const pixelMap = await imageSource.createPixelMap({ editable: true });
      const info = await pixelMap.getImageInfo();
      const imgW = info.size.width;
      const imgH = info.size.height;
      if (imgW <= 0 || imgH <= 0) {
        pixelMap.release();
        imageSource.release();
        return null;
      }

      const rect = PortraitCropUtil.computeCropRect(imgW, imgH, spec);
      await pixelMap.crop({
        x: rect.x,
        y: rect.y,
        size: { width: rect.width, height: rect.height }
      });

      const croppedInfo = await pixelMap.getImageInfo();
      const packer = image.createImagePacker();
      const jpegBuffer = await packer.packToData(pixelMap, {
        format: 'image/jpeg',
        quality: CROP_JPEG_QUALITY
      });

      packer.release();
      pixelMap.release();
      imageSource.release();

      console.info(
        `[PortraitCropUtil] 头像裁切 ${imgW}x${imgH} -> ` +
        `${croppedInfo.size.width}x${croppedInfo.size.height} ` +
        `@(${rect.x},${rect.y})`
      );

      return {
        data: jpegBuffer,
        width: croppedInfo.size.width,
        height: croppedInfo.size.height,
        format: 'jpeg'
      };
    } catch (err) {
      console.error('[PortraitCropUtil] 裁切失败', JSON.stringify(err));
      return null;
    }
  }

  /** 预览 UI 椭圆 → 成片像素裁切框（按预览占比映射） */
  private static computeCropRect(imgW: number, imgH: number, spec: FaceGuideCropSpec): CropRect {
    const viewW = Math.max(1, spec.viewWidthPx);
    const viewH = Math.max(1, spec.viewHeightPx);
    const ovalW = spec.ovalWidthRatio * viewW;
    const ovalH = ovalW / spec.ovalAspect;
    const leftOnView = (viewW - ovalW) / 2;
    const topOnView = Math.max(0, spec.ovalTopMarginPx);

    let x = Math.round((leftOnView / viewW) * imgW);
    let y = Math.round((topOnView / viewH) * imgH);
    let width = Math.round((ovalW / viewW) * imgW);
    let height = Math.round((ovalH / viewH) * imgH);

    if (x + width > imgW) {
      width = imgW - x;
    }
    if (y + height > imgH) {
      height = imgH - y;
    }
    if (width < 32 || height < 32) {
      // 极端情况下回退为居中竖向头像框
      width = Math.round(imgW * spec.ovalWidthRatio);
      height = Math.round(width / spec.ovalAspect);
      x = Math.round((imgW - width) / 2);
      y = Math.round((imgH - height) * 0.12);
    }

    x = Math.max(0, Math.min(x, imgW - 1));
    y = Math.max(0, Math.min(y, imgH - 1));
    width = Math.max(32, Math.min(width, imgW - x));
    height = Math.max(32, Math.min(height, imgH - y));

    return { x: x, y: y, width: width, height: height };
  }
}
