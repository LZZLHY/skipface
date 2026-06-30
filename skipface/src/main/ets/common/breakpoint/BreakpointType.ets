/**
 * BreakpointType.ets
 * 分层：common / 响应式断点
 *
 * 职责：定义 HarmonyOS「一多」的断点枚举与一个按断点取值的泛型工具。
 *
 * 断点划分（以窗口宽度 vp 为准）：
 *  - SM : [0, 600)    手机竖屏
 *  - MD : [600, 840)  折叠展开 / 手机横屏 / 小平板
 *  - LG : [840, +∞)   平板横屏 / 2in1 / 大屏
 */
export enum WidthBreakpoint {
  SM = 'sm',
  MD = 'md',
  LG = 'lg'
}

/** mediaquery 使用的宽度边界（vp）。 */
export class BreakpointBounds {
  static readonly MD_MIN: number = 600;
  static readonly LG_MIN: number = 840;
  private constructor() {}
}

/**
 * 按断点取值的工具：在不同断点下返回不同的值（数值/字符串/任意类型）。
 * 用法：new BreakpointValue<number>({ sm: 1, md: 2, lg: 3 }).get(currentBp)
 * 缺省回退：lg→md→sm，sm 必填。
 */
export class BreakpointValue<T> {
  private readonly sm: T;
  private readonly md?: T;
  private readonly lg?: T;

  constructor(values: BreakpointValueOptions<T>) {
    this.sm = values.sm;
    this.md = values.md;
    this.lg = values.lg;
  }

  /** 根据当前断点返回对应取值，未配置时向更小断点回退。 */
  get(bp: WidthBreakpoint): T {
    if (bp === WidthBreakpoint.LG) {
      return this.lg ?? this.md ?? this.sm;
    }
    if (bp === WidthBreakpoint.MD) {
      return this.md ?? this.sm;
    }
    return this.sm;
  }
}

/** BreakpointValue 的构造入参。sm 必填，md/lg 可选。 */
export interface BreakpointValueOptions<T> {
  sm: T;
  md?: T;
  lg?: T;
}
