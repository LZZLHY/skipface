/**
 * Logger.ets
 * 分层：common / 工具
 *
 * 职责：对 @kit.PerformanceAnalysisKit 的 hilog 做轻量封装，统一日志域(domain)、
 *       统一 TAG 前缀，并提供 debug/info/warn/error 四个级别。
 *
 * 约定：
 *  - 全应用使用同一个 DOMAIN，方便在 HiLog 中按域过滤。
 *  - 业务侧调用时传入模块级 tag（如 'EditorVM'），便于定位来源。
 *  - 仅记录必要信息，避免输出图像像素、用户隐私等大体量/敏感数据。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

/** HiLog 业务域。0x0000~0xFFFF 之间自定义，便于过滤本应用日志。 */
const LOG_DOMAIN: number = 0xF1AC;
/** 全局统一前缀，配合模块 tag 形成 "SkipFace/<tag>"。 */
const LOG_PREFIX: string = 'SkipFace';

export class Logger {
  /** 调试日志：仅开发期关注，发布包可被裁剪。 */
  static debug(tag: string, message: string): void {
    hilog.debug(LOG_DOMAIN, `${LOG_PREFIX}/${tag}`, '%{public}s', message);
  }

  /** 常规信息日志：关键流程节点。 */
  static info(tag: string, message: string): void {
    hilog.info(LOG_DOMAIN, `${LOG_PREFIX}/${tag}`, '%{public}s', message);
  }

  /** 警告日志：非致命异常、降级路径。 */
  static warn(tag: string, message: string): void {
    hilog.warn(LOG_DOMAIN, `${LOG_PREFIX}/${tag}`, '%{public}s', message);
  }

  /**
   * 错误日志：失败路径。
   * @param error 可选的异常对象，会附加其 message 以便排查。
   */
  static error(tag: string, message: string, error?: Error): void {
    const detail: string = error ? `${message} | ${error.name}: ${error.message}` : message;
    hilog.error(LOG_DOMAIN, `${LOG_PREFIX}/${tag}`, '%{public}s', detail);
  }
}
