/**
 * .om 端侧模型加载器（阶段 3）
 * MindSpore Lite 加载 + 三模型推理（支持单模型分步验证）
 */
import { common } from '@kit.AbilityKit';
import { OmModelKey } from './OmModelLoaderKeys';
import { MindSporeModelRunner } from './MindSporeModelRunner';
import { OmConfigLoader } from './OmConfigLoader';
import { OmModelConfigRoot, OmModelInputConfig, ComplexionEmbeddingTable } from './OmModelTypes';
import { VisionImagePreprocessor } from './VisionImagePreprocessor';
import { CapturedImage } from '../../common/types/AppTypes';

/** rawfile 相对路径（.om 与 .ms 内容格式相同，均为 MindSpore Lite buffer） */
const OM_MODEL_PATHS: Record<OmModelKey, string> = {
  [OmModelKey.MTCNN]: 'models/mtcnn.om',
  [OmModelKey.MOBILENETV3]: 'models/mobilenetv3.om',
  [OmModelKey.MOBILECLIP]: 'models/mobileclip.om'
};

export { OmModelKey } from './OmModelLoaderKeys';

export class OmModelLoader {
  private runners: Map<OmModelKey, MindSporeModelRunner> = new Map();
  private modelBuffers: Map<OmModelKey, ArrayBuffer> = new Map();
  private modelConfig: OmModelConfigRoot | null = null;
  private embeddingTable: ComplexionEmbeddingTable | null = null;
  private loadedRunnerCount: number = 0;

  /** 加载配置、词表 embedding，并按文件存在情况逐个初始化 MindSpore */
  async loadAll(context: common.UIAbilityContext): Promise<void> {
    await this.releaseAll();
    this.modelConfig = await OmConfigLoader.loadModelConfig(context);
    this.embeddingTable = await OmConfigLoader.loadEmbeddingTable(context);

    const resourceManager = context.resourceManager;
    for (const key of [OmModelKey.MTCNN, OmModelKey.MOBILENETV3, OmModelKey.MOBILECLIP]) {
      try {
        const rawBytes: Uint8Array = await resourceManager.getRawFileContent(OM_MODEL_PATHS[key]);
        const copiedBuffer: ArrayBuffer = new ArrayBuffer(rawBytes.byteLength);
        new Uint8Array(copiedBuffer).set(rawBytes);
        this.modelBuffers.set(key, copiedBuffer);
      } catch (_err) {
        // 单模型缺失时不阻塞，便于分步只放 mtcnn.om 验证
      }
    }

    if (this.modelBuffers.size === 0) {
      console.info('[OmModelLoader] rawfile/models/ 无 .om 文件，MindSpore 未启动');
      return;
    }

    let loadedCount = 0;
    for (const key of [OmModelKey.MTCNN, OmModelKey.MOBILENETV3, OmModelKey.MOBILECLIP]) {
      const buffer = this.modelBuffers.get(key);
      if (buffer === undefined) {
        continue;
      }
      const runner = new MindSporeModelRunner();
      const ok = await runner.loadFromBuffer(key, buffer);
      if (ok) {
        this.runners.set(key, runner);
        loadedCount++;
      }
    }

    this.loadedRunnerCount = loadedCount;
    console.info(
      `[OmModelLoader] 文件=${this.modelBuffers.size}/3, Runner=${loadedCount}/3, 全量就绪=${this.isMindSporeReady()}`
    );
  }

  isAllLoaded(): boolean {
    return this.modelBuffers.size === 3;
  }

  hasAnyModel(): boolean {
    return this.modelBuffers.size > 0;
  }

  hasModel(key: OmModelKey): boolean {
    return this.modelBuffers.has(key);
  }

  /** 单个模型 MindSpore Runner 是否可用 */
  isRunnerReady(key: OmModelKey): boolean {
    return this.runners.has(key);
  }

  /** 三模型全部加载成功 */
  isMindSporeReady(): boolean {
    return this.loadedRunnerCount === 3;
  }

  getModelConfig(key: OmModelKey): OmModelInputConfig | null {
    if (this.modelConfig === null) {
      return null;
    }
    if (key === OmModelKey.MTCNN) {
      return this.modelConfig.mtcnn;
    }
    if (key === OmModelKey.MOBILENETV3) {
      return this.modelConfig.mobilenetv3;
    }
    return this.modelConfig.mobileclip;
  }

  getEmbeddingTable(): ComplexionEmbeddingTable | null {
    return this.embeddingTable;
  }

  /**
   * 对指定模型执行推理，返回全部输出 tensor
   */
  async predictImageAll(key: OmModelKey, captured: CapturedImage): Promise<Float32Array[] | null> {
    if (!this.isRunnerReady(key)) {
      return null;
    }
    const runner = this.runners.get(key);
    const config = this.getModelConfig(key);
    if (runner === undefined || config === null) {
      return null;
    }

    const floatInput = await VisionImagePreprocessor.toFloat32Input(captured, config);
    if (floatInput === null) {
      return null;
    }
    const inputBuffer = VisionImagePreprocessor.float32ToBuffer(floatInput);
    return await runner.predictAll(inputBuffer);
  }

  /** 仅返回第一个输出（单输出模型） */
  async predictImage(key: OmModelKey, captured: CapturedImage): Promise<Float32Array | null> {
    const all = await this.predictImageAll(key, captured);
    if (all === null || all.length === 0) {
      return null;
    }
    return all[0];
  }

  async releaseAll(): Promise<void> {
    for (const runner of this.runners.values()) {
      await runner.release();
    }
    this.runners.clear();
    this.modelBuffers.clear();
    this.loadedRunnerCount = 0;
  }
}
