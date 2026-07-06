/**
 * .om 模型与 MindSpore 推理相关类型
 */
/** 输入张量内存布局：NHWC 或 NCHW（需与 MindSpore 转换参数一致） */
export type OmTensorLayout = 'NHWC' | 'NCHW';

/** 人脸检测后处理类型（与 ONNX 来源对应） */
export type FaceDetectorType = 'simple5' | 'ultraface';

export interface OmModelInputConfig {
  inputWidth: number;
  inputHeight: number;
  scale: number;
  meanR: number;
  meanG: number;
  meanB: number;
  /** 默认 NHWC；UltraFace 等 ONNX 模型通常为 NCHW */
  dataFormat?: OmTensorLayout;
  /** Stage1 检测器输出解析方式，默认 simple5 */
  detectorType?: FaceDetectorType;
}

/** MindSpore 推理原始输出 */
export interface OmRawInferenceOutput {
  data: Float32Array;
  length: number;
}

/** 气色词表 embedding 表 */
export interface ComplexionEmbeddingTable {
  dimension: number;
  tags: string[];
  vectors: number[][];
}

/** model_config.json 根结构 */
export interface OmModelConfigRoot {
  mtcnn: OmModelInputConfig;
  mobilenetv3: OmModelInputConfig;
  mobileclip: OmModelInputConfig;
}
