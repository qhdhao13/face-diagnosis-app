/**
 * .om 模型输出解析
 * 兼容常见 MTCNN / 分割 / CLIP embedding 输出布局
 */
import { FaceBoundingBox, FaceRegionRect } from '../../common/types/AppTypes';
import { FaceRegionLayout } from './FaceRegionLayout';

export class OmOutputParser {
  /**
   * 解析 UltraFace / 类似双输出检测器
   * 自动识别 scores(N*2) 与 boxes(N*4) 两个 tensor
   */
  static parseUltraFaceOutputs(
    outputs: Float32Array[],
    inputW: number,
    inputH: number,
    scoreThreshold: number = 0.7
  ): FaceBoundingBox | null {
    if (outputs.length < 2) {
      return null;
    }

    let scores: Float32Array | null = null;
    let boxes: Float32Array | null = null;

    for (let i = 0; i < outputs.length; i++) {
      const tensor = outputs[i];
      if (tensor.length % 2 === 0 && tensor.length % 4 !== 0) {
        scores = tensor;
      } else if (tensor.length % 4 === 0) {
        boxes = tensor;
      }
    }

    if (scores === null || boxes === null) {
      // 按长度 fallback：较短且为 2 的倍数视为 scores
      if (outputs[0].length * 2 === outputs[1].length) {
        scores = outputs[0];
        boxes = outputs[1];
      } else if (outputs[1].length * 2 === outputs[0].length) {
        scores = outputs[1];
        boxes = outputs[0];
      } else {
        return null;
      }
    }

    const anchorCount = Math.min(Math.floor(scores.length / 2), Math.floor(boxes.length / 4));
    if (anchorCount <= 0) {
      return null;
    }

    let bestIdx = -1;
    let bestScore = scoreThreshold;

    for (let i = 0; i < anchorCount; i++) {
      const faceProb = scores[i * 2 + 1];
      if (faceProb > bestScore) {
        bestScore = faceProb;
        bestIdx = i;
      }
    }

    if (bestIdx < 0) {
      return null;
    }

    const b = bestIdx * 4;
    let x1 = boxes[b];
    let y1 = boxes[b + 1];
    let x2 = boxes[b + 2];
    let y2 = boxes[b + 3];

    // 像素坐标 → 归一化
    if (x2 > 1.5 || y2 > 1.5) {
      x1 = x1 / inputW;
      y1 = y1 / inputH;
      x2 = x2 / inputW;
      y2 = y2 / inputH;
    }

    const x = OmOutputParser.clamp01(Math.min(x1, x2));
    const y = OmOutputParser.clamp01(Math.min(y1, y2));
    const width = OmOutputParser.clamp01(Math.abs(x2 - x1));
    const height = OmOutputParser.clamp01(Math.abs(y2 - y1));

    if (width < 0.08 || height < 0.08) {
      return null;
    }

    return {
      x: x,
      y: y,
      width: width,
      height: height,
      confidence: Math.min(1, Math.max(0, bestScore))
    };
  }

  /** 根据 model_config.detectorType 选择解析方式 */
  static parseFaceDetectOutputs(
    outputs: Float32Array[],
    inputW: number,
    inputH: number,
    detectorType: string | undefined
  ): FaceBoundingBox | null {
    if (detectorType === 'ultraface') {
      const ultra = OmOutputParser.parseUltraFaceOutputs(outputs, inputW, inputH);
      if (ultra !== null) {
        return ultra;
      }
    }
    if (outputs.length >= 1) {
      return OmOutputParser.parseMtcnnFaceBox(outputs[0]);
    }
    return null;
  }

  /**
   * 解析单输出人脸框
   * 支持 [x,y,w,h,score] 或 [x1,y1,x2,y2,score] 归一化坐标
   */
  static parseMtcnnFaceBox(output: Float32Array): FaceBoundingBox | null {
    if (output.length < 5) {
      return null;
    }

    let x = output[0];
    let y = output[1];
    let third = output[2];
    let fourth = output[3];
    let score = output[4];

    // 若为 x1,y1,x2,y2 格式则转换
    if (fourth > third && fourth <= 1.0 && third <= 1.0 && fourth > 0.05) {
      const x2 = third;
      const y2 = fourth;
      x = Math.min(x, x2);
      y = Math.min(y, y2);
      third = Math.abs(x2 - output[0]);
      fourth = Math.abs(y2 - output[1]);
    }

    if (third <= 0 || fourth <= 0) {
      return null;
    }

    // 像素坐标转归一化
    if (x > 1.5 || y > 1.5 || third > 1.5 || fourth > 1.5) {
      const maxSide = Math.max(x, y, third, fourth, 1);
      x = x / maxSide;
      y = y / maxSide;
      third = third / maxSide;
      fourth = fourth / maxSide;
    }

    x = OmOutputParser.clamp01(x);
    y = OmOutputParser.clamp01(y);
    const width = OmOutputParser.clamp01(third);
    const height = OmOutputParser.clamp01(fourth);

    if (width < 0.08 || height < 0.08) {
      return null;
    }

    return {
      x: x,
      y: y,
      width: width,
      height: height,
      confidence: Math.min(1, Math.max(0, score))
    };
  }

  /**
   * 解析 MobileNetV3 分割 mask → 面部分区
   * mask 长度应为 maskW*maskH；若无有效 mask 则返回 null
   */
  static parseSegmentationMask(
    output: Float32Array,
    faceBox: FaceBoundingBox,
    maskW: number,
    maskH: number
  ): FaceRegionRect[] | null {
    if (output.length < maskW * maskH) {
      return null;
    }

    // 当前模型未训练专用分割头时，用语义分区近似：仍基于 faceBox 动态微调
    const regions = FaceRegionLayout.buildRegions(faceBox);
    const avgActivation = OmOutputParser.meanMask(output, maskW * maskH);
    if (avgActivation < 0.01) {
      return null;
    }
    return regions;
  }

  /** MobileCLIP 输出即 embedding 向量 */
  static extractClipEmbedding(output: Float32Array): Float32Array {
    return output;
  }

  private static meanMask(data: Float32Array, count: number): number {
    let sum = 0;
    const n = Math.min(count, data.length);
    for (let i = 0; i < n; i++) {
      sum += Math.abs(data[i]);
    }
    return n > 0 ? sum / n : 0;
  }

  private static clamp01(v: number): number {
    return Math.max(0, Math.min(1, v));
  }
}
