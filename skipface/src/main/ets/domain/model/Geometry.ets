/**
 * Geometry.ets
 * 分层：domain / 模型（纯数据 + 几何工具）
 *
 * 职责：提供 PointF 与 RectF 两个基础几何类型，以及与"旋转椭圆命中检测"相关的工具。
 *
 * 坐标系约定：本文件中的坐标默认处于"代理显示图"坐标系（origin 左上，x 向右，y 向下）。
 *            导出时由上层按缩放比换算到原图坐标系。
 */

/** 二维点（浮点）。 */
export class PointF {
  x: number;
  y: number;

  constructor(x: number, y: number) {
    this.x = x;
    this.y = y;
  }

  /** 返回一个拷贝，避免共享可变引用。 */
  copy(): PointF {
    return new PointF(this.x, this.y);
  }
}

/**
 * 轴对齐矩形（以左/上/右/下表示）。
 * 注意：旋转信息不在 RectF 内，由持有它的遮挡对象单独保存 angle。
 */
export class RectF {
  left: number;
  top: number;
  right: number;
  bottom: number;

  constructor(left: number, top: number, right: number, bottom: number) {
    this.left = left;
    this.top = top;
    this.right = right;
    this.bottom = bottom;
  }

  /** 由中心点与宽高构造矩形。 */
  static fromCenter(cx: number, cy: number, width: number, height: number): RectF {
    const halfW: number = width / 2;
    const halfH: number = height / 2;
    return new RectF(cx - halfW, cy - halfH, cx + halfW, cy + halfH);
  }

  get width(): number {
    return this.right - this.left;
  }

  get height(): number {
    return this.bottom - this.top;
  }

  get centerX(): number {
    return (this.left + this.right) / 2;
  }

  get centerY(): number {
    return (this.top + this.bottom) / 2;
  }

  /** 返回按比例缩放(围绕原点)的新矩形，用于代理图 → 原图换算。 */
  scaled(factor: number): RectF {
    return new RectF(this.left * factor, this.top * factor, this.right * factor, this.bottom * factor);
  }

  /** 围绕自身中心，按 factor 缩放宽高得到新矩形（保持中心不变）。 */
  resizedAroundCenter(factor: number): RectF {
    return RectF.fromCenter(this.centerX, this.centerY, this.width * factor, this.height * factor);
  }

  /** 平移得到新矩形（用于拖动移动遮挡）。 */
  translated(dx: number, dy: number): RectF {
    return new RectF(this.left + dx, this.top + dy, this.right + dx, this.bottom + dy);
  }

  copy(): RectF {
    return new RectF(this.left, this.top, this.right, this.bottom);
  }
}

/**
 * 判断一个点是否落在"旋转后的椭圆"内部。
 * 原理：把点平移到椭圆中心，再反向旋转 angle，回到标准椭圆坐标系，
 *      最后用标准椭圆方程 x²/a² + y²/b² ≤ 1 判断。
 *
 * @param point  待判定点（与 rect 同坐标系）。
 * @param rect   椭圆外接矩形（半长轴 a = width/2，半短轴 b = height/2）。
 * @param angleDeg 椭圆的旋转角度（度，逆时针为正，与渲染保持一致）。
 */
export function isPointInRotatedEllipse(point: PointF, rect: RectF, angleDeg: number): boolean {
  const a: number = rect.width / 2;
  const b: number = rect.height / 2;
  if (a <= 0 || b <= 0) {
    return false;
  }
  // 平移到中心
  const tx: number = point.x - rect.centerX;
  const ty: number = point.y - rect.centerY;
  // 反向旋转 -angle
  const rad: number = (-angleDeg * Math.PI) / 180;
  const cos: number = Math.cos(rad);
  const sin: number = Math.sin(rad);
  const rx: number = tx * cos - ty * sin;
  const ry: number = tx * sin + ty * cos;
  // 标准椭圆方程
  return (rx * rx) / (a * a) + (ry * ry) / (b * b) <= 1;
}

/** 判断点是否落在以 (cx,cy) 为圆心、diameter 为直径的圆内（Emoji 命中检测）。 */
export function isPointInCircle(point: PointF, cx: number, cy: number, diameter: number): boolean {
  const dx: number = point.x - cx;
  const dy: number = point.y - cy;
  const radius: number = diameter / 2;
  return dx * dx + dy * dy <= radius * radius;
}
