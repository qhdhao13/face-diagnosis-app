/**
 * 加载 rawfile 下的 model_config.json 与 complexion_tag_embeddings.json
 */
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { ComplexionEmbeddingTable, OmModelConfigRoot, OmModelInputConfig } from './OmModelTypes';

const MODEL_CONFIG_PATH: string = 'models/model_config.json';
const EMBEDDING_TABLE_PATH: string = 'models/complexion_tag_embeddings.json';

/** 默认 MTCNN 输入配置（rawfile 缺失时使用） */
const DEFAULT_MTCNN: OmModelInputConfig = {
  inputWidth: 320,
  inputHeight: 240,
  scale: 0.0078125,
  meanR: 127.5,
  meanG: 127.5,
  meanB: 127.5
};

const DEFAULT_MOBILENET: OmModelInputConfig = {
  inputWidth: 224,
  inputHeight: 224,
  scale: 1 / 255,
  meanR: 0,
  meanG: 0,
  meanB: 0
};

export class OmConfigLoader {
  static async loadModelConfig(context: common.UIAbilityContext): Promise<OmModelConfigRoot> {
    try {
      const rawBytes: Uint8Array = await context.resourceManager.getRawFileContent(MODEL_CONFIG_PATH);
      const decoder = util.TextDecoder.create('utf-8');
      const text = decoder.decodeToString(rawBytes);
      const parsed = JSON.parse(text) as OmModelConfigRoot;
      return parsed;
    } catch (err) {
      console.warn('[OmConfigLoader] model_config.json 缺失，使用内置默认', JSON.stringify(err));
      return {
        mtcnn: DEFAULT_MTCNN,
        mobilenetv3: DEFAULT_MOBILENET,
        mobileclip: DEFAULT_MOBILENET
      };
    }
  }

  static async loadEmbeddingTable(context: common.UIAbilityContext): Promise<ComplexionEmbeddingTable | null> {
    try {
      const rawBytes: Uint8Array = await context.resourceManager.getRawFileContent(EMBEDDING_TABLE_PATH);
      const decoder = util.TextDecoder.create('utf-8');
      const text = decoder.decodeToString(rawBytes);
      return JSON.parse(text) as ComplexionEmbeddingTable;
    } catch (err) {
      console.warn('[OmConfigLoader] complexion_tag_embeddings.json 缺失', JSON.stringify(err));
      return null;
    }
  }
}
