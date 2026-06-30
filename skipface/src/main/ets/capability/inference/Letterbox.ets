/**
 * Letterbox.ets
 * 分层：capability / 推理能力（预处理）
 *
 * 职责：把任意尺寸的 PixelMap 预处理为 YOLOv8 所需的输入张量：
 *   1) 等比缩放并居中填充(letterbox)到 INPUT_SIZE×INPUT_SIZE，空白填中性灰；
 *   2) 归一化到 [0,1]，按 CHW(先 R 平面，后 G、B)排布为 Float32Array；
 *   3) 记录 scale / padX / padY 供后处理把坐标还原回原(代理)图坐标系。
 *
 * 坐标系：输入像素为"代理显示图"坐标；输出张量为"模型输入"坐标(640²)。
 * 实现说明：采用最近邻反向采样(对每个输出像素反推源像素)，无需依赖画布合成 API，
 *          结果稳定、可移植；对检测精度而言最近邻已足够。
 */
import { image } from '@kit.ImageKit';
import { AppConstants } from '../../common/constants/AppConstants';

/** 预处理结果：张量 + 还原所需的缩放与填充偏移。 */
export interface LetterboxResult {
  /** [1,3,S,S] 的 CHW 归一化数据(此处为扁平的 Float32Array，长度 3*S*S)。 */
  tensor: Float32Array;
  /** tensor 背后的 ArrayBuffer(显式分配，便于以 nominal ArrayBuffer 传给推理 API)。 */
  buffer: ArrayBuffer;
  /** 源(代理图) → 模型输入 的等比缩放系数。 */
  scale: number;
  /** 水平填充(模型输入坐标，像素)。 */
  padX: number;
  /** 垂直填充(模型输入坐标，像素)。 */
  padY: number;
}

export class Letterbox {
  /**
   * 执行预处理。
   * @param pixelMap 源 PixelMap（要求 RGBA_8888）。
   */
  static async preprocess(pixelMap: image.PixelMap): Promise<LetterboxResult> {
    const info: image.ImageInfo = await pixelMap.getImageInfo();
    const srcW: number = info.size.width;
    const srcH: number = info.size.height;
    const S: number = AppConstants.MODEL_INPUT_SIZE;

    // 1) 计算等比缩放与居中填充。
    const scale: number = Math.min(S / srcW, S / srcH);
    const newW: number = srcW * scale;
    const newH: number = srcH * scale;
    const padX: number = (S - newW) / 2;
    const padY: number = (S - newH) / 2;

    // 2) 读取源像素到缓冲(RGBA8888，每像素 4 字节，行无额外对齐)。
    const byteCount: number = pixelMap.getPixelBytesNumber();
    const srcBuffer: ArrayBuffer = new ArrayBuffer(byteCount);
    await pixelMap.readPixelsToBuffer(srcBuffer);
    const src: Uint8Array = new Uint8Array(srcBuffer);
    const srcStride: number = srcW * 4; // RGBA8888 行字节数

    // 3) 准备 CHW 张量；先整体填中性灰(归一化值)，再覆盖有效区域。
    //    显式分配 ArrayBuffer 并在其上建立视图，便于以 nominal ArrayBuffer 传给推理 API。
    const plane: number = S * S;
    const buffer: ArrayBuffer = new ArrayBuffer(3 * plane * Float32Array.BYTES_PER_ELEMENT);
    const tensor: Float32Array = new Float32Array(buffer);
    const grayNorm: number = AppConstants.LETTERBOX_PAD_GRAY / 255;
    tensor.fill(grayNorm);

    const norm: number = 1 / 255;
    // 遍历模型输入坐标，反向采样源像素(最近邻)。
    for (let oy: number = 0; oy < S; oy++) {
      // 反推源纵坐标
      const sy: number = (oy - padY) / scale;
      if (sy < 0 || sy >= srcH) {
        continue; // 落在填充区，保持灰
      }
      const syi: number = Math.min(srcH - 1, Math.max(0, Math.floor(sy)));
      const rowBase: number = syi * srcStride;
      const outRow: number = oy * S;
      for (let ox: number = 0; ox < S; ox++) {
        const sx: number = (ox - padX) / scale;
        if (sx < 0 || sx >= srcW) {
          continue; // 填充区，保持灰
        }
        const sxi: number = Math.min(srcW - 1, Math.max(0, Math.floor(sx)));
        const p: number = rowBase + sxi * 4;
        const idx: number = outRow + ox;
        // 归一化并写入 CHW 三个平面
        tensor[idx] = src[p] * norm;                 // R 平面
        tensor[plane + idx] = src[p + 1] * norm;      // G 平面
        tensor[2 * plane + idx] = src[p + 2] * norm;  // B 平面
      }
    }

    return { tensor, buffer, scale, padX, padY };
  }

  private constructor() {}
}
