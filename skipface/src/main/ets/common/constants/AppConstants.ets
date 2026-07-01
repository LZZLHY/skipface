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
  static readonly SCORE_THRESHOLD: number = 0.25;

  /** ====== 图像处理 ====== */
  /** 检测/编辑使用的代理图最大边长（性能与精度平衡）。 */
  static readonly DISPLAY_MAX_SIDE: number = 1024;
  /**
   * 人脸检测自适应细分参数。系统检测器每次调用最多返回约 10 张脸；对多人合影，
   * 若一次调用返回数达到该阈值，说明结果被截断，则把该区域切成带重叠的四块分别再检测，
   * 反复细分直到某块不足阈值，最后合并 + NMS 去重，用"多次调用"突破"单次数量上限"。
   */
  static readonly DETECT_SUBDIVIDE_THRESHOLD: number = 8;
  /** 细分最大深度(整图=0；1→4 块；2→16 块；3→64 块，仅拥挤区域才会展开)。 */
  static readonly DETECT_MAX_DEPTH: number = 3;
  /** 允许继续细分的最小区域边长(原图像素)：低于此值不再切，避免切出系统拒绝的过小块。 */
  static readonly DETECT_MIN_SPLIT: number = 320;
  /**
   * 系统检测器可接受的最小输入边长(像素)。解码后短边小于此值的块直接跳过检测——
   * 这类过小块会触发 "parameter check failed" 报错、白白消耗调用预算，且几乎无有效人脸。
   */
  static readonly DETECT_MIN_INPUT: number = 256;
  /** 细分时相邻子块的重叠比例，避免骑跨边界的人脸被切断漏检。 */
  static readonly DETECT_SPLIT_OVERLAP: number = 0.3;
  /** 检测调用总次数上限(安全阀，避免极端图片过度细分导致耗时过长)。 */
  static readonly DETECT_MAX_CALLS: number = 96;
  /** 单块解码的最大边长(原图像素)：超过则降采样解码，限制内存/耗时。 */
  static readonly DETECT_REGION_MAX: number = 2200;
  /** 分块结果合并去重的 IoU 阈值：重叠超过该值视为同一张脸，保留分数更高者。 */
  static readonly DETECT_DEDUP_IOU: number = 0.45;
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
