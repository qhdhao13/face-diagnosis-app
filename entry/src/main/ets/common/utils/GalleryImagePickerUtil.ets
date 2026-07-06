/**
 * 相册选图工具
 * 通过系统 PhotoViewPicker 选择已有照片，读入内存供色诊分析（不写磁盘、不入相册）
 */
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { CapturedImage } from '../types/AppTypes';

export class GalleryImagePickerUtil {
  /**
   * 打开系统相册，选择一张人像照片
   * @returns 内存中的图像；用户取消选择时返回 null
   */
  static async pickPortraitImage(): Promise<CapturedImage | null> {
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const options = new photoAccessHelper.PhotoSelectOptions();
      // 仅允许选择静态图片
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;

      const result = await picker.select(options);
      if (result === undefined || result.photoUris === undefined || result.photoUris.length === 0) {
        return null;
      }

      const uri = result.photoUris[0];
      if (uri.length === 0) {
        return null;
      }
      return await GalleryImagePickerUtil.readUriAsCapturedImage(uri);
    } catch (err) {
      console.error('[GalleryImagePickerUtil] 相册选图失败', JSON.stringify(err));
      return null;
    }
  }

  /**
   * 将 picker 返回的 URI 读入 ArrayBuffer，并解析宽高
   */
  private static async readUriAsCapturedImage(uri: string): Promise<CapturedImage | null> {
    let file: fileIo.File | null = null;
    try {
      file = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY);
      const stat = fileIo.statSync(file.fd);
      if (stat.size <= 0) {
        return null;
      }

      const buffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      file = null;

      const imageSource = image.createImageSource(buffer);
      const info = await imageSource.getImageInfo();
      imageSource.release();

      const width = info.size.width;
      const height = info.size.height;
      if (width <= 0 || height <= 0) {
        return null;
      }

      return {
        data: buffer,
        width: width,
        height: height,
        // 相册可能是 JPEG/PNG/WebP，后续 ImageKit 会统一解码
        format: 'jpeg'
      };
    } catch (err) {
      console.error('[GalleryImagePickerUtil] 读取相册图片失败', JSON.stringify(err));
      if (file !== null) {
        try {
          fileIo.closeSync(file);
        } catch (_closeErr) {
          // 忽略关闭失败
        }
      }
      return null;
    }
  }
}
