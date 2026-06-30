/**
 * MaskPainter.ets
 * 分层：capability / 图像处理（统一绘制器）
 *
 * 职责：把"遮挡对象"绘制到任意 2D 画布上下文(CanvasRenderer)。预览与导出复用同一套绘制逻辑：
 *   - 预览：传入屏幕 Canvas 的上下文，坐标为"代理图"空间(scale=1)，base 缓冲为代理图。
 *   - 导出：传入离屏 Canvas 的上下文，坐标为"原图"空间(遮挡已按比例放大)，base 缓冲为原图。
 *
 * 关键点：
 *   - Emoji：translate→rotate→fillText，字号=直径，居中基线。
 *   - 模糊  ：抽取旋转对齐区域→效果算法→区域 PixelMap→旋转+椭圆裁剪后 drawImage。
 *
 * 注意：调用方需先把 base 图像绘制到 ctx，再调用本绘制器叠加遮挡。
 */
import { image } from '@kit.ImageKit';
import { EmojiMask, BlurMask } from '../../domain/model/Mask';
import { BlurEffect } from '../../domain/model/MaskEnums';
import { BlurAlgorithms } from './BlurAlgorithms';
import { PixelMapUtil, RgbaBuffer } from './PixelMapUtil';

/** 不同效果的自适应参数(与算法基调一致)。 */
class EffectParams {
  static readonly GAUSSIAN_DIVISOR: number = 120;
  static readonly GAUSSIAN_CELLS: number = 10;
  static readonly PIXELATE_DIVISOR: number = 80;
  static readonly PIXELATE_CELLS: number = 12;
  static readonly HALFTONE_DIVISOR: number = 70;
  static readonly HALFTONE_CELLS: number = 12;
}

export class MaskPainter {
  /**
   * emoji 字号 = 人脸框直径 × 该系数(对所有 emoji 统一，保证大小一致)。
   * 经真机校准：本平台彩色 emoji 字形的可视墨迹仅约为 font-size 的 1/3，故需较大系数，
   * 使视觉直径≈人脸框、足以盖住整张脸。统一系数避免逐个测量带来的忽大忽小。
   */
  private static readonly EMOJI_DRAW_RATIO: number = 3.0;

  /**
   * 绘制单个 Emoji 遮挡。
   * @param ctx        2D 上下文(基图已绘制)。
   * @param mask       Emoji 遮挡(坐标与 ctx 同空间)。
   * @param fontFamily 可选自定义字体族名(需提前注册)。
   */
  static paintEmoji(ctx: CanvasRenderer, mask: EmojiMask, fontFamily?: string): void {
    ctx.save();
    ctx.translate(mask.centerX, mask.centerY);
    ctx.rotate((mask.angle * Math.PI) / 180);
    // 字体名含空格(如 "HarmonyOS Sans")必须加引号，否则整条 font 解析失败、字号回退默认 14px。
    const family: string = fontFamily && fontFamily.length > 0 ? `"${fontFamily}"` : 'sans-serif';
    const drawSize: number = mask.diameter * MaskPainter.EMOJI_DRAW_RATIO;
    ctx.font = `${drawSize}px ${family}`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(mask.emoji, 0, 0);
    ctx.restore();
  }

  /**
   * 绘制单个模糊遮挡。
   * @param ctx     2D 上下文(基图已绘制)。
   * @param mask    模糊遮挡(坐标与 ctx 同空间)。
   * @param baseBuf 与 ctx 同空间的基图 RGBA 缓冲(用于抽取区域内容)。
   * @param effect  模糊效果类型。
   */
  static async paintBlur(
    ctx: CanvasRenderer, mask: BlurMask, baseBuf: RgbaBuffer, effect: BlurEffect
  ): Promise<void> {
    const rectW: number = Math.max(1, Math.round(mask.rect.width));
    const rectH: number = Math.max(1, Math.round(mask.rect.height));
    if (rectW < 2 || rectH < 2) {
      return;
    }

    // 1) 抽取旋转对齐的区域内容。
    const chunk: RgbaBuffer = PixelMapUtil.extractRegionChunk(
      baseBuf, mask.rect.centerX, mask.rect.centerY, rectW, rectH, mask.angle
    );

    // 2) 按效果处理。
    const processed: Uint8Array = MaskPainter.applyEffect(chunk, effect, baseBuf.width, baseBuf.height);
    const regionBuffer: RgbaBuffer = { data: processed, width: chunk.width, height: chunk.height };
    const regionPixelMap: image.PixelMap = await PixelMapUtil.createFromRgba(regionBuffer);

    // 3) 旋转 + 椭圆裁剪后贴回。绘制完成后释放本次临时 PixelMap，
    //    否则预览/导出每次重绘都会创建一张区域图而从不回收，造成原生内存快速累积。
    ctx.save();
    try {
      ctx.translate(mask.rect.centerX, mask.rect.centerY);
      ctx.rotate((mask.angle * Math.PI) / 180);
      ctx.beginPath();
      ctx.ellipse(0, 0, rectW / 2, rectH / 2, 0, 0, Math.PI * 2);
      ctx.clip();
      ctx.drawImage(regionPixelMap, -rectW / 2, -rectH / 2, rectW, rectH);
    } finally {
      ctx.restore();
      regionPixelMap.release().catch((): void => {});
    }
  }

  /** 按效果类型对区域小图应用算法，返回处理后缓冲。 */
  private static applyEffect(chunk: RgbaBuffer, effect: BlurEffect, imgW: number, imgH: number): Uint8Array {
    switch (effect) {
      case BlurEffect.PIXELATE: {
        const cell: number = BlurAlgorithms.adaptiveCellSize(
          chunk.width, chunk.height, imgW, imgH, EffectParams.PIXELATE_DIVISOR, EffectParams.PIXELATE_CELLS
        );
        return BlurAlgorithms.pixelate(chunk.data, chunk.width, chunk.height, cell);
      }
      case BlurEffect.HALFTONE: {
        const cell: number = BlurAlgorithms.adaptiveCellSize(
          chunk.width, chunk.height, imgW, imgH, EffectParams.HALFTONE_DIVISOR, EffectParams.HALFTONE_CELLS
        );
        return BlurAlgorithms.halftone(chunk.data, chunk.width, chunk.height, cell);
      }
      case BlurEffect.GAUSSIAN:
      default: {
        const radius: number = BlurAlgorithms.adaptiveCellSize(
          chunk.width, chunk.height, imgW, imgH, EffectParams.GAUSSIAN_DIVISOR, EffectParams.GAUSSIAN_CELLS
        );
        return BlurAlgorithms.gaussianBlur(chunk.data, chunk.width, chunk.height, radius);
      }
    }
  }

  private constructor() {}
}
