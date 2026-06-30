/**
 * BuildBlurMasksUseCase.ets
 * 分层：domain / 用例（纯逻辑）
 *
 * 职责：把人脸检测结果转换为模糊遮挡区域列表。
 *   - FACE 目标：区域矩形 = 人脸框；
 *   - EYES 目标：以双眼中点为中心，宽 = 眼距 × 1.8，高 = 宽 × 0.5；
 *   - 角度均取两眼连线角度，最终以旋转椭圆裁剪。
 */
import { FaceDetection } from '../model/FaceDetection';
import { BlurMask } from '../model/Mask';
import { BlurTarget } from '../model/MaskEnums';
import { RectF, PointF } from '../model/Geometry';

export class BuildBlurMasksUseCase {
  /** 眼部条带相对眼距的宽度系数。 */
  private static readonly EYES_WIDTH_FACTOR: number = 1.8;
  /** 眼部条带高宽比。 */
  private static readonly EYES_HEIGHT_RATIO: number = 0.5;

  /**
   * @param detections 人脸检测结果(代理图坐标系)。
   * @param target     遮挡目标(面部/眼部)。
   */
  execute(detections: FaceDetection[], target: BlurTarget): BlurMask[] {
    const masks: BlurMask[] = [];
    for (const det of detections) {
      const angle: number = det.landmarks.eyeAngleDeg;
      let rect: RectF;
      if (target === BlurTarget.EYES) {
        const center: PointF = det.landmarks.eyeCenter;
        const width: number = det.landmarks.eyeDistance * BuildBlurMasksUseCase.EYES_WIDTH_FACTOR;
        const height: number = width * BuildBlurMasksUseCase.EYES_HEIGHT_RATIO;
        rect = RectF.fromCenter(center.x, center.y, width, height);
      } else {
        rect = det.box.copy();
      }
      masks.push(new BlurMask(rect, angle));
    }
    return masks;
  }
}
