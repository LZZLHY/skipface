/**
 * PlaceEmojiMasksUseCase.ets
 * 分层：domain / 用例（纯逻辑）
 *
 * 职责：把人脸检测结果转换为 Emoji 遮挡列表。
 *   - 圆心 = 人脸框中心；
 *   - 直径 = 在"宽"与"对角线"之间按长宽差异比插值(避免方框拉伸)；
 *   - 角度 = 两眼连线角度(跟随头部倾斜)；
 *   - emoji = 从调色板"不重复随机"选取，用尽后重置。
 *
 * 无副作用、无外部依赖，便于单测。
 */
import { FaceDetection } from '../model/FaceDetection';
import { EmojiMask } from '../model/Mask';

export class PlaceEmojiMasksUseCase {
  /**
   * @param detections 人脸检测结果(代理图坐标系)。
   * @param palette    可用 emoji 列表。
   */
  execute(detections: FaceDetection[], palette: string[]): EmojiMask[] {
    const available: string[] = palette.length > 0 ? palette : ['🙂'];
    // 按 x 排序，使分配顺序稳定、可预期。
    const sorted: FaceDetection[] = detections.slice().sort(
      (a: FaceDetection, b: FaceDetection): number => a.box.centerX - b.box.centerX
    );
    let pool: string[] = available.slice();
    const masks: EmojiMask[] = [];

    for (const det of sorted) {
      const w: number = det.box.width;
      const h: number = det.box.height;
      const maxSide: number = Math.max(w, h);
      const diffRatio: number = maxSide > 0 ? Math.abs(w - h) / maxSide : 0;
      const diagonal: number = Math.hypot(w, h);
      const diameter: number = w * (1 - diffRatio) + diagonal * diffRatio;
      const angle: number = det.landmarks.eyeAngleDeg;

      if (pool.length === 0) {
        pool = available.slice();
      }
      const idx: number = Math.floor(Math.random() * pool.length);
      const emoji: string = pool.splice(idx, 1)[0];

      masks.push(new EmojiMask(det.box.centerX, det.box.centerY, diameter, angle, emoji));
    }
    return masks;
  }
}
