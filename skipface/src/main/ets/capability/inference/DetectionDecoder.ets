/**
 * DetectionDecoder.ets
 * 分层：capability / 推理能力（后处理）
 *
 * 职责：把 YOLOv8-face 的原始输出张量解码为业务可用的 FaceDetection 列表：
 *   1) 解析通道布局，按置信度阈值过滤；
 *   2) 把框/关键点从"模型输入坐标"还原回"代理图坐标"(减 padding、除 scale)；
 *   3) 非极大值抑制(NMS)去重。
 *
 * 输出张量约定(YOLOv8 导出常见布局)：形状 [1, C, A]，通道优先(channel-major)，
 *   访问第 c 通道、第 i 个 anchor 的值为 output[c*A + i]。
 *   通道含义：0 cx, 1 cy, 2 w, 3 h, 4 score, 其后为 5 个关键点；
 *   每关键点步长 kptStep = (C-5)/5，可能为 2(x,y) 或 3(x,y,conf)。
 */
import { AppConstants } from '../../common/constants/AppConstants';
import { PointF, RectF } from '../../domain/model/Geometry';
import { FaceDetection, FaceLandmarks } from '../../domain/model/FaceDetection';

/** 解码中间体：边角框 + 关键点 + 分数。 */
interface RawBox {
  left: number;
  top: number;
  right: number;
  bottom: number;
  score: number;
  keypoints: PointF[];
}

export class DetectionDecoder {
  /**
   * 解码 + NMS。
   * @param output    模型输出扁平数组(长度 = C*A)。
   * @param scale     letterbox 缩放系数。
   * @param padX      水平填充。
   * @param padY      垂直填充。
   */
  static decode(output: Float32Array, scale: number, padX: number, padY: number): FaceDetection[] {
    const numAnchors: number = AppConstants.NUM_ANCHORS;
    const total: number = output.length;
    const numChannels: number = Math.floor(total / numAnchors);
    if (numChannels < 5) {
      return []; // 通道数异常，直接返回空
    }
    const hasKeypoints: boolean = numChannels >= 15;
    const kptStep: number = hasKeypoints ? Math.floor((numChannels - 5) / AppConstants.NUM_KEYPOINTS) : 0;

    const boxes: RawBox[] = [];
    for (let i: number = 0; i < numAnchors; i++) {
      const score: number = output[4 * numAnchors + i];
      if (score < AppConstants.SCORE_THRESHOLD) {
        continue;
      }
      const cx: number = output[0 * numAnchors + i];
      const cy: number = output[1 * numAnchors + i];
      const w: number = output[2 * numAnchors + i];
      const h: number = output[3 * numAnchors + i];

      // 模型坐标 → 代理图坐标(减 padding 再除 scale)。
      const left: number = (cx - w / 2 - padX) / scale;
      const top: number = (cy - h / 2 - padY) / scale;
      const right: number = (cx + w / 2 - padX) / scale;
      const bottom: number = (cy + h / 2 - padY) / scale;

      const keypoints: PointF[] = [];
      if (hasKeypoints) {
        for (let k: number = 0; k < AppConstants.NUM_KEYPOINTS; k++) {
          const kxCh: number = 5 + k * kptStep;
          const kyCh: number = kxCh + 1;
          const kx: number = (output[kxCh * numAnchors + i] - padX) / scale;
          const ky: number = (output[kyCh * numAnchors + i] - padY) / scale;
          keypoints.push(new PointF(kx, ky));
        }
      }

      boxes.push({ left, top, right, bottom, score, keypoints });
    }

    return DetectionDecoder.nms(boxes);
  }

  /** 非极大值抑制：按分数降序，抑制 IoU 超阈值的重叠框。 */
  private static nms(boxes: RawBox[]): FaceDetection[] {
    boxes.sort((a: RawBox, b: RawBox): number => b.score - a.score);
    const active: boolean[] = new Array<boolean>(boxes.length).fill(true);
    const result: FaceDetection[] = [];

    for (let i: number = 0; i < boxes.length; i++) {
      if (!active[i]) {
        continue;
      }
      const b: RawBox = boxes[i];
      result.push(DetectionDecoder.toDetection(b, result.length));
      for (let j: number = i + 1; j < boxes.length; j++) {
        if (active[j] && DetectionDecoder.iou(b, boxes[j]) > AppConstants.IOU_THRESHOLD) {
          active[j] = false;
        }
      }
    }
    return result;
  }

  /** 计算两个边角框的 IoU。 */
  private static iou(a: RawBox, b: RawBox): number {
    const x1: number = Math.max(a.left, b.left);
    const y1: number = Math.max(a.top, b.top);
    const x2: number = Math.min(a.right, b.right);
    const y2: number = Math.min(a.bottom, b.bottom);
    const inter: number = Math.max(0, x2 - x1) * Math.max(0, y2 - y1);
    const areaA: number = Math.max(0, a.right - a.left) * Math.max(0, a.bottom - a.top);
    const areaB: number = Math.max(0, b.right - b.left) * Math.max(0, b.bottom - b.top);
    const union: number = areaA + areaB - inter;
    return union <= 0 ? 0 : inter / union;
  }

  /** 把中间体转为领域模型 FaceDetection。 */
  private static toDetection(b: RawBox, index: number): FaceDetection {
    const box: RectF = new RectF(b.left, b.top, b.right, b.bottom);
    // 关键点缺失时用框推断一个保守的近似(避免后续空指针)。
    const kp: PointF[] = b.keypoints;
    const landmarks: FaceLandmarks = new FaceLandmarks(
      kp[0] ?? new PointF(box.left + box.width * 0.35, box.top + box.height * 0.4),
      kp[1] ?? new PointF(box.left + box.width * 0.65, box.top + box.height * 0.4),
      kp[2] ?? new PointF(box.centerX, box.centerY),
      kp[3] ?? new PointF(box.left + box.width * 0.38, box.top + box.height * 0.72),
      kp[4] ?? new PointF(box.left + box.width * 0.62, box.top + box.height * 0.72)
    );
    const id: string = `det_${Date.now().toString(36)}_${index}`;
    return new FaceDetection(id, box, landmarks, b.score);
  }

  private constructor() {}
}
