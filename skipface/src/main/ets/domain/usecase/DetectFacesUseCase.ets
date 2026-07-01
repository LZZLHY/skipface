/**
 * DetectFacesUseCase.ets
 * 分层：domain / 用例
 *
 * 职责：对代理图执行人脸检测，返回 FaceDetection 列表。
 * 依赖：FaceDetector 抽象(默认实现为系统 Core Vision Kit 的 CoreVisionFaceDetector)。
 */
import { image } from '@kit.ImageKit';
import { FaceDetector } from '../../capability/inference/FaceDetector';
import { FaceDetection } from '../model/FaceDetection';
import { Result } from '../../common/base/Result';

export class DetectFacesUseCase {
  private readonly detector: FaceDetector;

  constructor(detector: FaceDetector) {
    this.detector = detector;
  }

  /** @param proxy 代理显示图(RGBA_8888)。 */
  async execute(proxy: image.PixelMap): Promise<Result<FaceDetection[]>> {
    return Result.runAsync<FaceDetection[]>(async (): Promise<FaceDetection[]> => {
      if (!this.detector.isLoaded()) {
        await this.detector.load();
      }
      return this.detector.detect(proxy);
    });
  }
}
