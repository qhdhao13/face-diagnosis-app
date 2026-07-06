/**
 * 面部分区布局工具
 * 将「人脸框内相对分区」映射到整图归一化坐标，供规则引擎与 .om 管线共用
 */
import { FaceBoundingBox, FaceRegionRect } from '../../common/types/AppTypes';

/** 相对于人脸框（0-1）的标准分区模板 */
interface RelativeRegionTemplate {
  name: string;
  xStart: number;
  xEnd: number;
  yStart: number;
  yEnd: number;
}

export class FaceRegionLayout {
  private static readonly FACE_RELATIVE_TEMPLATES: RelativeRegionTemplate[] = [
    { name: '额头', xStart: 0.15, xEnd: 0.85, yStart: 0.02, yEnd: 0.28 },
    { name: '左脸颊', xStart: 0.05, xEnd: 0.45, yStart: 0.30, yEnd: 0.58 },
    { name: '右脸颊', xStart: 0.55, xEnd: 0.95, yStart: 0.30, yEnd: 0.58 },
    { name: '鼻部', xStart: 0.35, xEnd: 0.65, yStart: 0.25, yEnd: 0.52 },
    { name: '下巴', xStart: 0.25, xEnd: 0.75, yStart: 0.58, yEnd: 0.92 },
    { name: '眼周', xStart: 0.10, xEnd: 0.90, yStart: 0.22, yEnd: 0.38 },
    { name: '唇部', xStart: 0.30, xEnd: 0.70, yStart: 0.68, yEnd: 0.88 }
  ];

  /** 无检测框时使用的默认可取景区域（假设人脸居中） */
  private static readonly DEFAULT_FACE_BOX: FaceBoundingBox = {
    x: 0.15,
    y: 0.10,
    width: 0.70,
    height: 0.80,
    confidence: 0.5
  };

  /** 根据人脸框生成分区列表 */
  static buildRegions(faceBox?: FaceBoundingBox): FaceRegionRect[] {
    const box = faceBox ?? FaceRegionLayout.DEFAULT_FACE_BOX;
    const regions: FaceRegionRect[] = [];

    for (const template of FaceRegionLayout.FACE_RELATIVE_TEMPLATES) {
      regions.push({
        name: template.name,
        xStart: FaceRegionLayout.clamp01(box.x + template.xStart * box.width),
        xEnd: FaceRegionLayout.clamp01(box.x + template.xEnd * box.width),
        yStart: FaceRegionLayout.clamp01(box.y + template.yStart * box.height),
        yEnd: FaceRegionLayout.clamp01(box.y + template.yEnd * box.height)
      });
    }
    return regions;
  }

  /** 全脸统计区域 */
  static buildGlobalRegion(faceBox?: FaceBoundingBox): FaceRegionRect {
    const box = faceBox ?? FaceRegionLayout.DEFAULT_FACE_BOX;
    return {
      name: '全脸',
      xStart: FaceRegionLayout.clamp01(box.x),
      xEnd: FaceRegionLayout.clamp01(box.x + box.width),
      yStart: FaceRegionLayout.clamp01(box.y),
      yEnd: FaceRegionLayout.clamp01(box.y + box.height)
    };
  }

  private static clamp01(value: number): number {
    return Math.max(0, Math.min(1, value));
  }
}
