/**
 * MindSpore Lite 模型运行器
 * 封装 loadModelFromBuffer / predict / 释放
 */
import { mindSporeLite } from '@kit.MindSporeLiteKit';

export class MindSporeModelRunner {
  private model: mindSporeLite.Model | null = null;
  private modelName: string = '';

  /** 从内存 buffer 加载 .om / .ms 模型 */
  async loadFromBuffer(modelName: string, modelBuffer: ArrayBuffer): Promise<boolean> {
    await this.release();
    try {
      const context: mindSporeLite.Context = {
        target: ['cpu'],
        cpu: {
          threadNum: 2,
          threadAffinityMode: 1,
          precisionMode: 'enforce_fp32'
        }
      };
      this.model = await mindSporeLite.loadModelFromBuffer(modelBuffer, context);
      this.modelName = modelName;
      console.info(`[MindSporeModelRunner] 模型已加载: ${modelName}, bytes=${modelBuffer.byteLength}`);
      return true;
    } catch (err) {
      console.error(`[MindSporeModelRunner] 加载失败 ${modelName}`, JSON.stringify(err));
      this.model = null;
      return false;
    }
  }

  /** 执行推理，返回全部输出 tensor（UltraFace 等多输出模型需要） */
  async predictAll(inputBuffer: ArrayBuffer): Promise<Float32Array[] | null> {
    if (this.model === null) {
      return null;
    }
    try {
      const modelInputs: mindSporeLite.MSTensor[] = this.model.getInputs();
      if (modelInputs.length === 0) {
        console.error(`[MindSporeModelRunner] ${this.modelName} 无输入 tensor`);
        return null;
      }

      modelInputs[0].setData(inputBuffer);

      const outputs: mindSporeLite.MSTensor[] = await this.model.predict(modelInputs);
      if (outputs.length === 0) {
        console.error(`[MindSporeModelRunner] ${this.modelName} 无输出 tensor`);
        return null;
      }

      const result: Float32Array[] = [];
      for (let i = 0; i < outputs.length; i++) {
        const outBuffer: ArrayBuffer = outputs[i].getData();
        result.push(new Float32Array(outBuffer.slice(0, outBuffer.byteLength)));
        console.info(`[MindSporeModelRunner] ${this.modelName} 输出[${i}] len=${result[i].length}`);
      }
      return result;
    } catch (err) {
      console.error(`[MindSporeModelRunner] 推理失败 ${this.modelName}`, JSON.stringify(err));
      return null;
    }
  }

  /** 执行推理，仅返回第一个输出（单输出模型） */
  async predict(inputBuffer: ArrayBuffer): Promise<Float32Array | null> {
    const all = await this.predictAll(inputBuffer);
    if (all === null || all.length === 0) {
      return null;
    }
    return all[0];
  }

  /** MindSpore Lite Model 无显式 release API，置空引用由 GC 回收 */
  async release(): Promise<void> {
    if (this.model !== null) {
      console.info(`[MindSporeModelRunner] 卸载模型: ${this.modelName}`);
      this.model = null;
      this.modelName = '';
    }
  }
}
