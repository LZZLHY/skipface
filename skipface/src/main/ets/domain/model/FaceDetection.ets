/**
 * FaceDetection.ets
 * 分层：domain / 模型
 *
 * 职责：描述一次人脸检测的结果（边界框 + 5 关键点 + 置信度）。
 *       坐标处于"代理显示图"坐标系。
 *
 * 关键点顺序（YOLOv8-face 约定）：
 *   0 左眼, 1 右眼, 2 鼻尖, 3 左嘴角, 4 右嘴角
 */
import { PointF, RectF } from './Geometry';

/** 5 个人脸关键点。 */
export class FaceLandmarks {
  leftEye: PointF;
  rightEye: PointF;
  nose: PointF;
  mouthLeft: PointF;
  mouthRight: PointF;

  constructor(
    leftEye: PointF,
    rightEye: PointF,
    nose: PointF,
    mouthLeft: PointF,
    mouthRight: PointF
  ) {
    this.leftEye = leftEye;
    this.rightEye = rightEye;
    this.nose = nose;
    this.mouthLeft = mouthLeft;
    this.mouthRight = mouthRight;
  }

  /**
   * 两眼连线的角度（度）。用于让 Emoji / 模糊区域跟随头部倾斜。
   * 约定：atan2(dy, dx)，返回值与渲染所用的旋转角度一致。
   */
  get eyeAngleDeg(): number {
    const dx: number = this.rightEye.x - this.leftEye.x;
    const dy: number = this.rightEye.y - this.leftEye.y;
    return (Math.atan2(dy, dx) * 180) / Math.PI;
  }

  /** 两眼之间的距离（像素）。 */
  get eyeDistance(): number {
    const dx: number = this.rightEye.x - this.leftEye.x;
    const dy: number = this.rightEye.y - this.leftEye.y;
    return Math.hypot(dx, dy);
  }

  /** 两眼中点。 */
  get eyeCenter(): PointF {
    return new PointF(
      (this.leftEye.x + this.rightEye.x) / 2,
      (this.leftEye.y + this.rightEye.y) / 2
    );
  }
}

/** 一次人脸检测结果。 */
export class FaceDetection {
  /** 唯一 id（用于列表 diff / 关联遮挡）。 */
  readonly id: string;
  /** 人脸边界框（代理图坐标系）。 */
  readonly box: RectF;
  /** 5 关键点。 */
  readonly landmarks: FaceLandmarks;
  /** 置信度 [0,1]。 */
  readonly score: number;

  constructor(id: string, box: RectF, landmarks: FaceLandmarks, score: number) {
    this.id = id;
    this.box = box;
    this.landmarks = landmarks;
    this.score = score;
  }
}
