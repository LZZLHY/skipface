/**
 * AppConstants.ets
 * 分层：common / 常量
 *
 * 职责：集中存放与业务无关的全局常量（模型、推理、图像处理、持久化键等）。
 *       业务语义的"枚举"放在 domain/model/MaskEnums.ets，避免混淆。
 */
export class AppConstants {
  /** ====== 检测 ====== */
  /** 置信度阈值：低于此分数的人脸检测结果被丢弃。取较低值以提升人群照的召回。 */
  static readonly SCORE_THRESHOLD: number = 0.3;

  /** ====== 图像处理 ====== */
  /** 检测/编辑使用的代理图最大边长（性能与精度平衡）。 */
  static readonly DISPLAY_MAX_SIDE: number = 1024;
  /**
   * 人脸检测专用图的最大边长。人群/毕业照中人脸在 1024 代理图上过小(20~30px)会被系统
   * 检测器漏检；单独解码一张更大的图做检测(用后即释放)，再把坐标按比例映射回代理图空间，
   * 显著提升多人小脸的召回。编辑仍用小代理图，内存不受影响。
   */
  static readonly DETECT_MAX_SIDE: number = 2560;
  /** 新增 Emoji 的默认直径（代理图坐标系，像素）。 */
  static readonly DEFAULT_EMOJI_DIAMETER: number = 100;
  /** 新增模糊区域的默认边长（代理图坐标系，像素）。 */
  static readonly DEFAULT_BLUR_SIZE: number = 200;
  /** Emoji 大小可调范围（相对 originalDiameter 的比例）。 */
  static readonly SIZE_FACTOR_MIN: number = 0.5;
  static readonly SIZE_FACTOR_MAX: number = 2.5;
  /**
   * 角度可调范围（度）。覆盖完整一圈，使倾斜/倒置人脸的角度也能被滑块
   * 完整表示与保留，避免编辑时把检测得到的角度夹断。
   */
  static readonly ANGLE_MIN: number = -180;
  static readonly ANGLE_MAX: number = 180;

  /** ====== 持久化 ====== */
  /** Preferences 文件名。 */
  static readonly PREF_STORE_NAME: string = 'skipface_settings';

  /** ====== 关于 ====== */
  /** 开源仓库地址（设置页“关于”内点击跳转系统浏览器）。 */
  static readonly GITHUB_URL: string = 'https://github.com/LZZLHY/skipface';
  /** 隐私政策页面地址（首次启动同意弹窗与设置页入口跳转）。 */
  static readonly PRIVACY_URL: string = 'https://lzzlhy.github.io/skipface/privacy.html';

  private constructor() {}
}

/** Preferences 中使用的键名集中管理，避免散落的魔法字符串。 */
export class PrefKeys {
  static readonly EMOJI_PALETTE: string = 'emoji_palette';
  static readonly SELECTED_FONT: string = 'selected_font';
  static readonly FONT_LIST: string = 'font_list';
  static readonly DEFAULT_MASK_KIND: string = 'default_mask_kind';
  static readonly DEFAULT_BLUR_EFFECT: string = 'default_blur_effect';
  static readonly DEFAULT_BLUR_TARGET: string = 'default_blur_target';
  static readonly THEME_MODE: string = 'theme_mode';
  /** 是否已同意隐私政策（首次启动同意门控）。 */
  static readonly PRIVACY_AGREED: string = 'privacy_agreed';
  /** 是否允许自动布置表情时重复使用同一表情。 */
  static readonly ALLOW_EMOJI_REPEAT: string = 'allow_emoji_repeat';

  private constructor() {}
}
