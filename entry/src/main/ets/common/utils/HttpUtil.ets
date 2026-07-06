/**
 * 轻量 HTTP 工具
 * 封装 NetworkKit 请求，供版本检测与模型 API 调用复用
 */
import { http } from '@kit.NetworkKit';

/** HTTP 响应封装 */
export interface HttpResponse {
  ok: boolean;
  statusCode: number;
  body: string;
}

export class HttpUtil {
  /**
   * 发起 GET 请求
   * @param url 完整请求地址
   * @param headers 可选请求头
   */
  static async get(url: string, headers?: Record<string, string>): Promise<HttpResponse> {
    return HttpUtil.request(url, http.RequestMethod.GET, undefined, headers);
  }

  /**
   * 发起 POST 请求
   * @param url 完整请求地址
   * @param body 请求体（JSON 字符串）
   * @param headers 可选请求头
   */
  static async post(
    url: string,
    body: string,
    headers?: Record<string, string>,
    readTimeoutMs: number = 15000
  ): Promise<HttpResponse> {
    return HttpUtil.request(url, http.RequestMethod.POST, body, headers, readTimeoutMs);
  }

  private static buildHeaders(headers?: Record<string, string>): Record<string, string> {
    if (headers !== undefined) {
      return headers;
    }
    const defaultHeaders: Record<string, string> = {};
    defaultHeaders['Content-Type'] = 'application/json';
    return defaultHeaders;
  }

  private static async request(
    url: string,
    method: http.RequestMethod,
    body?: string,
    headers?: Record<string, string>,
    readTimeoutMs: number = 15000
  ): Promise<HttpResponse> {
    const httpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: HttpUtil.buildHeaders(headers),
        connectTimeout: 15000,
        readTimeout: readTimeoutMs
      };
      if (body !== undefined) {
        options.extraData = body;
      }
      const response = await httpRequest.request(url, options);
      const statusCode = response.responseCode;
      const resultText = typeof response.result === 'string'
        ? response.result
        : JSON.stringify(response.result);
      return {
        ok: statusCode >= 200 && statusCode < 300,
        statusCode: statusCode,
        body: resultText
      };
    } catch (err) {
      console.error('[HttpUtil] 请求失败', JSON.stringify(err));
      return { ok: false, statusCode: -1, body: '' };
    } finally {
      httpRequest.destroy();
    }
  }
}
