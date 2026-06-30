/**
 * PixelMapUtil.ets
 * 分层：capability / 图像处理（PixelMap 工具）
 *
 * 职责：封装 PixelMap 与 RGBA 缓冲之间的互转、代理图缩放、以及"旋转区域抽取"。
 *       这些是渲染引擎(导出/预览)与模糊算法之间的桥梁。
 *
 * 坐标系：所有像素坐标均为传入 PixelMap 自身的像素坐标。
 */
import { image } from '@kit.ImageKit';

/** RGBA 缓冲及其尺寸。 */
export interface RgbaBuffer {
  data: Uint8Array;
  width: number;
  height: number;
}

export class PixelMapUtil {
  /** 读取 PixelMap 全部像素为 RGBA8888 缓冲。要求 pixelMap 为 RGBA_8888。 */
  static async readRgba(pixelMap: image.PixelMap): Promise<RgbaBuffer> {
    const info: image.ImageInfo = await pixelMap.getImageInfo();
    const width: number = info.size.width;
    const height: number = info.size.height;
    const byteCount: number = pixelMap.getPixelBytesNumber();
    const ab: ArrayBuffer = new ArrayBuffer(byteCount);
    await pixelMap.readPixelsToBuffer(ab);
    return { data: new Uint8Array(ab), width, height };
  }

  /** 由 RGBA 缓冲创建一个新的 PixelMap。 */
  static async createFromRgba(buffer: RgbaBuffer): Promise<image.PixelMap> {
    const options: image.InitializationOptions = {
      size: { width: buffer.width, height: buffer.height },
      srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      pixelFormat: image.PixelMapFormat.RGBA_8888,
      editable: true
    };
    // createPixelMap 需要 ArrayBuffer；传入底层 buffer。
    const ab: ArrayBuffer = buffer.data.buffer.slice(
      buffer.data.byteOffset, buffer.data.byteOffset + buffer.data.byteLength
    );
    return image.createPixelMap(ab, options);
  }

  /**
   * 抽取"旋转对齐"的区域内容：返回一张轴对齐的小图(宽 rectW × 高 rectH)，
   * 其内容是 base 在以 (centerX,centerY) 为中心、旋转 angleDeg 的矩形内的像素。
   * 之后对该小图做模糊/像素化/半色调，再以相同旋转+椭圆裁剪贴回，即可无缝替换。
   *
   * 映射(小图局部 → 源)：source = center + R(angle) · (Lx, Ly)，
   *   其中 (Lx,Ly) 为以小图中心为原点的局部坐标，R 为旋转矩阵。
   */
  static extractRegionChunk(
    base: RgbaBuffer,
    centerX: number, centerY: number,
    rectW: number, rectH: number,
    angleDeg: number
  ): RgbaBuffer {
    const w: number = Math.max(1, Math.round(rectW));
    const h: number = Math.max(1, Math.round(rectH));
    const out: Uint8Array = new Uint8Array(w * h * 4);
    const rad: number = (angleDeg * Math.PI) / 180;
    const cos: number = Math.cos(rad);
    const sin: number = Math.sin(rad);
    const halfW: number = w / 2;
    const halfH: number = h / 2;

    for (let ly: number = 0; ly < h; ly++) {
      const lyc: number = ly - halfH;
      for (let lx: number = 0; lx < w; lx++) {
        const lxc: number = lx - halfW;
        // 旋转局部坐标，加回中心 → 源坐标。
        const sx: number = centerX + (lxc * cos - lyc * sin);
        const sy: number = centerY + (lxc * sin + lyc * cos);
        const o: number = (ly * w + lx) * 4;
        if (sx < 0 || sx >= base.width || sy < 0 || sy >= base.height) {
          // 越界：透明(导出时该区域本就被椭圆裁剪掉)。
          out[o + 3] = 0;
          continue;
        }
        const sxi: number = Math.min(base.width - 1, Math.floor(sx));
        const syi: number = Math.min(base.height - 1, Math.floor(sy));
        const p: number = (syi * base.width + sxi) * 4;
        out[o] = base.data[p];
        out[o + 1] = base.data[p + 1];
        out[o + 2] = base.data[p + 2];
        out[o + 3] = 255;
      }
    }
    return { data: out, width: w, height: h };
  }

  private constructor() {}
}
