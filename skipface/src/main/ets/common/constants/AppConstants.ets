/**
 * AppConstants.ets
 * 分层：common / 常量
 *
 * 职责：集中存放与业务无关的全局常量（模型、推理、图像处理、持久化键等）。
 *       业务语义的"枚举"放在 domain/model/MaskEnums.ets，避免混淆。
 */
export class AppConstants {
  /** ====== 模型与推理 ====== */
  /** rawfile 中的 ONNX 模型文件名（默认实现，ONNX Runtime 直接加载）。 */
  static readonly ONNX_MODEL_FILE_NAME: string = 'skipface_face.onnx';
  /** rawfile 中的 MindSpore Lite 模型文件名（可选实现，需离线转换得到）。 */
  static readonly MS_MODEL_FILE_NAME: string = 'skipface_face.ms';
  /** 模型输入边长（letterbox 到 INPUT_SIZE×INPUT_SIZE）。 */
  static readonly MODEL_INPUT_SIZE: number = 640;
  /** letterbox 填充使用的中性灰（0~255）。 */
  static readonly LETTERBOX_PAD_GRAY: number = 114;
  /** YOLOv8 默认 anchor 数（640 输入下为 8400）。 */
  static readonly NUM_ANCHORS: number = 8400;
  /** 置信度阈值：低于此分数的框被丢弃。 */
  static readonly SCORE_THRESHOLD: number = 0.45;
  /** NMS 的 IoU 阈值：高于此重叠度的框被抑制。 */
  static readonly IOU_THRESHOLD: number = 0.5;
  /** 关键点数量（左眼/右眼/鼻/左嘴角/右嘴角）。 */
  static readonly NUM_KEYPOINTS: number = 5;

  /** ====== 图像处理 ====== */
  /** 检测/编辑使用的代理图最大边长（性能与精度平衡）。 */
  static readonly DISPLAY_MAX_SIDE: number = 1024;
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

  /** ====== 导出 ====== */
  /** 相册中保存的相对目录名。 */
  static readonly ALBUM_FOLDER: string = 'SkipFace';

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

  private constructor() {}
}
