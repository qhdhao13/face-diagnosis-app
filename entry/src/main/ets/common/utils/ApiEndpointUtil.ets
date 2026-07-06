/**
 * OpenAI 兼容 API 地址规范化
 * 通义文档中的 BASE_URL 与 HTTP POST 完整地址不同，此处自动补全
 */
export class ApiEndpointUtil {
  /**
   * 规范化为 chat/completions 完整 POST 地址
   * 支持用户填写：
   * - https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions（完整）
   * - https://dashscope.aliyuncs.com/compatible-mode/v1（BASE_URL，SDK 用）
   */
  static normalizeChatCompletionsEndpoint(endpoint: string): string {
    let url = endpoint.trim();
    if (url.length === 0) {
      return url;
    }

    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }

    if (url.endsWith('/chat/completions')) {
      return url;
    }

    if (url.endsWith('/v1')) {
      return `${url}/chat/completions`;
    }

    if (url.endsWith('/compatible-mode')) {
      return `${url}/v1/chat/completions`;
    }

    return url;
  }
}
