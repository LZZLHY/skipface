/**
 * ImageExporter.ets
 * 分层：capability / 图像处理（高清导出渲染）
 *
 * 职责：在原始全分辨率上重渲染最终图像并返回 PixelMap：
 *   1) 离屏画布 drawImage 原图；
 *   2) 把代理图坐标系的遮挡按 scaleToOriginal 放大到原图坐标系；
 *   3) 通过 MaskPainter 叠加 Emoji / 模糊；
 *   4) getImageData 取回像素并重建为 PixelMap。
 *
 * 说明：使用 OffscreenCanvas + 2D 上下文，单位为 PX 以保证 1:1 像素映射。
 */
import { image } from '@kit.ImageKit';
import { display } from '@kit.ArkUI';
import { EmojiMask, BlurMask } from '../../domain/model/Mask';
import { MaskKind, BlurEffect } from '../../domain/model/MaskEnums';
import { MaskPainter } from './MaskPainter';
import { PixelMapUtil, RgbaBuffer } from './PixelMapUtil';
import { Logger } from '../../common/utils/Logger';

/** 导出入参。 */
export interface ExportRequest {
  /** 原始全分辨率图像。 */
  original: image.PixelMap;
  /** 当前遮挡模式。 */
  maskKind: MaskKind;
  /** Emoji 遮挡列表(代理图坐标系)。 */
  emojiMasks: EmojiMask[];
  /** 模糊遮挡列表(代理图坐标系)。 */
  blurMasks: BlurMask[];
  /** 模糊效果类型。 */
  blurEffect: BlurEffect;
  /** 代理图 → 原图 的放大系数。 */
  scaleToOriginal: number;
  /** 可选自定义 emoji 字体族。 */
  fontFamily?: string;
}

export class ImageExporter {
  private static readonly TAG: string = 'ImageExporter';

  /**
   * 屏幕逻辑像素密度(vp→px 系数)。OffscreenCanvas 以 vp 为绘制单位，
   * 而 getImageData 取回的是物理像素(vp×density)。导出时据此换算，
   * 既保证输出 ≈ 原图分辨率，又避免在高密度设备上分配 density² 倍的画布内存。
   */
  private static density(): number {
    try {
      const d: number = display.getDefaultDisplaySync().densityPixels;
      return d && d > 0 ? d : 1;
    } catch (e) {
      Logger.warn(ImageExporter.TAG, 'read density failed, fallback to 1');
      return 1;
    }
  }

  /** 执行导出，返回渲染后的 PixelMap。 */
  static async export(req: ExportRequest): Promise<image.PixelMap> {
    const info: image.ImageInfo = await req.original.getImageInfo();
    const w: number = info.size.width;
    const h: number = info.size.height;
    const d: number = ImageExporter.density();

    // 画布以 vp 为单位：尺寸取 原图px/density，使物理像素 ≈ 原图分辨率(内存不爆)。
    // 再对上下文施加 1/density 缩放，使后续一切绘制都用"原图像素坐标"，物理上 1:1 映射，
    // 这样 MaskPainter 的 Emoji/模糊绘制逻辑无需任何改动。
    const offscreen: OffscreenCanvas = new OffscreenCanvas(w / d, h / d);
    const ctx: OffscreenCanvasRenderingContext2D = offscreen.getContext('2d');
    ctx.scale(1 / d, 1 / d);

    // 1) 绘制原图(原图像素坐标)。
    ctx.drawImage(req.original, 0, 0, w, h);

    const s: number = req.scaleToOriginal;
    if (req.maskKind === MaskKind.EMOJI) {
      // 2) Emoji：放大坐标后逐个绘制。
      for (const m of req.emojiMasks) {
        const scaled: EmojiMask = new EmojiMask(
          m.centerX * s, m.centerY * s, m.diameter * s, m.angle, m.emoji, m.id, m.originalDiameter * s
        );
        MaskPainter.paintEmoji(ctx, scaled, req.fontFamily);
      }
    } else {
      // 2) 模糊：需要原图 RGBA 缓冲用于区域抽取(与上面绘制同处原图像素坐标系)。
      const baseBuf: RgbaBuffer = await PixelMapUtil.readRgba(req.original);
      for (const m of req.blurMasks) {
        const scaled: BlurMask = new BlurMask(m.rect.scaled(s), m.angle, m.id, m.originalRect.scaled(s));
        await MaskPainter.paintBlur(ctx, scaled, baseBuf, req.blurEffect);
      }
    }

    // 3) 取回像素并重建 PixelMap。
    //    getImageData 的参数按 vp 计，返回的是物理像素，必须用 ImageData 的真实宽高重建，
    //    否则行跨距(stride)对不上 → 横条纹乱码。
    const imgData: ImageData = ctx.getImageData(0, 0, w / d, h / d);
    const outW: number = imgData.width;
    const outH: number = imgData.height;
    const out: Uint8Array = new Uint8Array(imgData.data.buffer.slice(0));
    const result: image.PixelMap = await PixelMapUtil.createFromRgba({ data: out, width: outW, height: outH });
    Logger.info(ImageExporter.TAG, `exported ${outW}x${outH} (origin ${w}x${h}, density ${d})`);
    return result;
  }

  private constructor() {}
}
