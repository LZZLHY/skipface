/**
 * Mask.ets
 * 分层：domain / 模型
 *
 * 职责：定义两类可编辑的遮挡对象：
 *   - EmojiMask：以圆心 + 直径 + 角度 + emoji 描述。
 *   - BlurMask ：以矩形(椭圆外接) + 角度描述，外加 originalRect 作为缩放基准。
 *
 * 这些对象坐标处于"代理显示图"坐标系；导出时上层按比例换算到原图后再渲染。
 * 对象提供 copyWith 风格的复制方法，配合不可变更新（状态层 copy-on-write）。
 */
import { RectF } from './Geometry';

/** 生成一个轻量唯一 id（时间戳高位 + 随机低位）。 */
function genId(): string {
  const ts: number = Date.now();
  const rnd: number = Math.floor(Math.random() * 0x100000);
  return `${ts.toString(36)}_${rnd.toString(36)}`;
}

/** Emoji 遮挡。 */
export class EmojiMask {
  readonly id: string;
  /** 圆心 X（代理图坐标）。 */
  centerX: number;
  /** 圆心 Y（代理图坐标）。 */
  centerY: number;
  /** 当前直径（像素），即绘制时的字号。 */
  diameter: number;
  /** 初始直径，用作大小滑块的 100% 基准。 */
  readonly originalDiameter: number;
  /** 旋转角度（度，逆时针为正）。 */
  angle: number;
  /** 显示的 emoji 字符（可为多字符的组合 emoji）。 */
  emoji: string;

  constructor(
    centerX: number,
    centerY: number,
    diameter: number,
    angle: number,
    emoji: string,
    id?: string,
    originalDiameter?: number
  ) {
    this.id = id ?? genId();
    this.centerX = centerX;
    this.centerY = centerY;
    this.diameter = diameter;
    this.angle = angle;
    this.emoji = emoji;
    this.originalDiameter = originalDiameter ?? diameter;
  }

  /** 返回一份深拷贝。 */
  clone(): EmojiMask {
    return new EmojiMask(
      this.centerX, this.centerY, this.diameter, this.angle, this.emoji, this.id, this.originalDiameter
    );
  }

  /** 基于比例因子设置直径（相对 originalDiameter）。 */
  withSizeFactor(factor: number): EmojiMask {
    const c: EmojiMask = this.clone();
    c.diameter = this.originalDiameter * factor;
    return c;
  }

  /** 当前直径相对原始直径的比例，用于回填滑块。 */
  get sizeFactor(): number {
    return this.originalDiameter > 0 ? this.diameter / this.originalDiameter : 1;
  }
}

/** 模糊遮挡区域。 */
export class BlurMask {
  readonly id: string;
  /** 当前矩形（椭圆外接，代理图坐标）。 */
  rect: RectF;
  /** 初始矩形，作为大小滑块的 100% 基准。 */
  readonly originalRect: RectF;
  /** 旋转角度（度，逆时针为正）。 */
  angle: number;

  constructor(rect: RectF, angle: number, id?: string, originalRect?: RectF) {
    this.id = id ?? genId();
    this.rect = rect;
    this.angle = angle;
    this.originalRect = originalRect ?? rect.copy();
  }

  clone(): BlurMask {
    return new BlurMask(this.rect.copy(), this.angle, this.id, this.originalRect.copy());
  }

  /** 基于比例因子重设大小（围绕中心，相对 originalRect）。 */
  withSizeFactor(factor: number): BlurMask {
    const c: BlurMask = this.clone();
    c.rect = this.originalRect.resizedAroundCenter(factor);
    return c;
  }

  /** 当前宽度相对原始宽度的比例，用于回填滑块。 */
  get sizeFactor(): number {
    const ow: number = this.originalRect.width;
    return ow > 0 ? this.rect.width / ow : 1;
  }
}
