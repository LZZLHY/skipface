/**
 * LoadedImage.ets
 * 分层：domain / 模型
 *
 * 职责：描述一张已加载图片用于"编辑"的表示。为降低内存占用，编辑期**不常驻全分辨率原图**，
 *       只保留代理显示图(proxy)与还原导出所需的元信息；导出时再按 uri 临时解码原图并即用即放。
 *   - uri            ：图片来源(选择器/分享/拍摄)，导出时据此重新解码原图；
 *   - proxy          ：代理显示图(检测与编辑使用，最大边受限)；
 *   - scaleToOriginal：代理→原图 的放大系数；
 *   - aspectRatio    ：原图宽高比，用于 UI 维持比例。
 */
import { image } from '@kit.ImageKit';

export class LoadedImage {
  /** 图片来源 uri(导出时按需重新解码全分辨率原图)。 */
  readonly uri: string;
  readonly proxy: image.PixelMap;
  readonly scaleToOriginal: number;
  readonly aspectRatio: number;
  /** 代理图像素宽高（用于在代理坐标系下做居中等几何计算）。 */
  readonly proxyWidth: number;
  readonly proxyHeight: number;

  constructor(
    uri: string,
    proxy: image.PixelMap,
    scaleToOriginal: number,
    aspectRatio: number,
    proxyWidth: number,
    proxyHeight: number
  ) {
    this.uri = uri;
    this.proxy = proxy;
    this.scaleToOriginal = scaleToOriginal;
    this.aspectRatio = aspectRatio;
    this.proxyWidth = proxyWidth;
    this.proxyHeight = proxyHeight;
  }
}
