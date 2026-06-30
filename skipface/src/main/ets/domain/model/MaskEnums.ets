/**
 * MaskEnums.ets
 * 分层：domain / 模型
 *
 * 职责：定义遮挡相关的业务枚举：遮挡模式、模糊效果、遮挡目标。
 *       数值与 Preferences 持久化整数一致，便于存取。
 */

/** 遮挡模式：用 Emoji 覆盖，或用模糊遮挡。 */
export enum MaskKind {
  EMOJI = 0,
  BLUR = 1
}

/** 模糊效果风格。 */
export enum BlurEffect {
  /** 高斯模糊。 */
  GAUSSIAN = 0,
  /** 像素化（马赛克块）。 */
  PIXELATE = 1,
  /** 半色调网点。 */
  HALFTONE = 2
}

/** 模糊作用目标。 */
export enum BlurTarget {
  /** 整张人脸。 */
  FACE = 0,
  /** 仅眼部条带。 */
  EYES = 1
}

/** 枚举与整型互转的工具，做边界保护。 */
export class MaskEnumUtil {
  static toMaskKind(value: number): MaskKind {
    return value === MaskKind.BLUR ? MaskKind.BLUR : MaskKind.EMOJI;
  }

  static toBlurEffect(value: number): BlurEffect {
    if (value === BlurEffect.PIXELATE) {
      return BlurEffect.PIXELATE;
    }
    if (value === BlurEffect.HALFTONE) {
      return BlurEffect.HALFTONE;
    }
    return BlurEffect.GAUSSIAN;
  }

  static toBlurTarget(value: number): BlurTarget {
    return value === BlurTarget.EYES ? BlurTarget.EYES : BlurTarget.FACE;
  }

  private constructor() {}
}
