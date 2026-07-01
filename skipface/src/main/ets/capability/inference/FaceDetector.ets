/**
 * FaceDetector.ets
 * 分层：capability / 推理能力（抽象）
 *
 * 职责：定义人脸检测器的统一接口，便于替换底层实现（系统视觉服务 / 自研模型 / 其它）。
 *       上层（用例/状态层）只依赖该接口，不感知具体检测框架。
 *       当前默认实现为 CoreVisionFaceDetector（系统 Core Vision Kit）。
 */
import { image } from '@kit.ImageKit';
import { FaceDetection } from '../../domain/model/FaceDetection';

export interface FaceDetector {
  /** 异步加载模型（含一次 warmup）。重复调用应幂等。 */
  load(): Promise<void>;

  /** 模型是否已就绪。 */
  isLoaded(): boolean;

  /**
   * 对给定 PixelMap 执行人脸检测。
   * @param pixelMap 期望为 RGBA_8888 格式的代理显示图（已缩放到 DISPLAY_MAX_SIDE 内）。
   * @returns 代理图坐标系下的检测结果列表（已做置信度过滤与 NMS）。
   */
  detect(pixelMap: image.PixelMap): Promise<FaceDetection[]>;

  /** 释放底层模型与会话资源。 */
  release(): Promise<void>;
}
