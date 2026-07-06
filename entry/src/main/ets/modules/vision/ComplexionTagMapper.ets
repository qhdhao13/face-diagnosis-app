/**
 * 气色标签映射器（阶段 3 · MobileCLIP embedding → 封闭词表）
 */
import { ComplexionTypes } from '../../common/constants/AppConstants';
import { ComplexionEmbeddingTable } from './OmModelTypes';

interface TagScore {
  tag: string;
  score: number;
}

export class ComplexionTagMapper {
  private static embeddingTable: ComplexionEmbeddingTable | null = null;

  /** 由 OmModelLoader 注入词表 embedding */
  static setEmbeddingTable(table: ComplexionEmbeddingTable | null): void {
    ComplexionTagMapper.embeddingTable = table;
  }

  static mapFromColorStats(
    avgR: number,
    avgG: number,
    avgB: number,
    brightness: number,
    saturation: number
  ): string {
    const scores: TagScore[] = [];

    if (brightness < 90) {
      scores.push({ tag: '偏暗沉', score: 1.0 });
      scores.push({ tag: '暗沉', score: 0.8 });
    }
    if (avgR > avgG + 18 && avgR > avgB + 18 && brightness > 120) {
      scores.push({ tag: '偏红', score: 1.0 });
      scores.push({ tag: '泛红', score: 0.7 });
    }
    if (avgG > avgR + 8 && avgG > avgB) {
      scores.push({ tag: '偏黄', score: 0.9 });
    }
    if (brightness > 175 && saturation < 0.18) {
      scores.push({ tag: '偏白', score: 0.9 });
      scores.push({ tag: '偏青白', score: 0.6 });
    }
    if (saturation > 0.35 && avgR > avgG + 15) {
      scores.push({ tag: '泛红', score: 0.85 });
    }
    if (brightness >= 90 && brightness <= 160 && scores.length === 0) {
      scores.push({ tag: '气色尚可', score: 0.7 });
    }

    if (scores.length === 0) {
      return '偏暗沉';
    }

    scores.sort((a: TagScore, b: TagScore) => b.score - a.score);
    const topTag = scores[0].tag;
    return ComplexionTypes.TYPES.includes(topTag) ? topTag : '气色尚可';
  }

  /** MobileCLIP embedding → cosine 最近邻封闭词表 */
  static mapFromEmbedding(embedding: Float32Array): string {
    const table = ComplexionTagMapper.embeddingTable;
    if (table === null || table.tags.length === 0) {
      return '气色尚可';
    }

    let bestTag = '气色尚可';
    let bestScore = -2;

    for (let i = 0; i < table.tags.length; i++) {
      const ref = table.vectors[i];
      const score = ComplexionTagMapper.cosineSimilarity(embedding, ref, table.dimension);
      if (score > bestScore) {
        bestScore = score;
        bestTag = table.tags[i];
      }
    }

    return ComplexionTypes.TYPES.includes(bestTag) ? bestTag : '气色尚可';
  }

  private static cosineSimilarity(a: Float32Array, b: number[], dim: number): number {
    const n = Math.min(dim, a.length, b.length);
    let dot = 0;
    let normA = 0;
    let normB = 0;
    for (let i = 0; i < n; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA <= 0 || normB <= 0) {
      return 0;
    }
    return dot / (Math.sqrt(normA) * Math.sqrt(normB));
  }
}
