/**
 * EditorViewModel.ets
 * 分层：状态层（@ObservedV2）
 *
 * 职责：编辑器页面的唯一状态来源与动作编排。持有可观察状态(@Trace)，
 *       通过用例完成加载/检测/定位/编辑/导出，UI 只读状态、发事件。
 *
 * 坐标系：所有遮挡坐标处于"代理图"空间；导出时由用例按比例换算到原图。
 * 不可变更新：对数组字段一律 copy-on-write(重新赋值)以触发 @Trace 刷新。
 */
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { AppContainer } from '../common/di/AppContainer';
import { LoadedImage } from '../domain/model/LoadedImage';
import { FaceDetection, FaceLandmarks } from '../domain/model/FaceDetection';
import { EmojiMask, BlurMask } from '../domain/model/Mask';
import { RectF, PointF } from '../domain/model/Geometry';
import { MaskKind, BlurEffect, BlurTarget } from '../domain/model/MaskEnums';
import { ExportRequest } from '../capability/imaging/ImageExporter';
import { Result } from '../common/base/Result';
import { AppConstants } from '../common/constants/AppConstants';
import { Logger } from '../common/utils/Logger';
import { EmojiUtil } from '../common/utils/EmojiUtil';
import { DEFAULT_FONT_MARKER } from '../data/settings/SettingsRepository';

/** 检测调用预算/状态(递归细分时跨调用累计)。 */
interface DetectBudget {
  /** 已发起的检测调用次数(用于总次数上限)。 */
  calls: number;
  /** 是否至少有一次检测成功(用于区分"检测异常"与"检测到 0 张")。 */
  anyOk: boolean;
}

/** 一次性 UI 提示事件(由 UI 消费后清空)。message 为字符串资源已解析或直接文案。 */
@ObservedV2
export class EditorViewModel {
  private static readonly TAG: string = 'EditorViewModel';

  // ====== 图像 ======
  @Trace loaded: LoadedImage | null = null;
  @Trace aspectRatio: number = 1;

  // ====== 检测与遮挡 ======
  @Trace detections: FaceDetection[] = [];
  @Trace emojiMasks: EmojiMask[] = [];
  @Trace blurMasks: BlurMask[] = [];

  // ====== 模式 ======
  @Trace maskKind: MaskKind = MaskKind.EMOJI;
  @Trace blurEffect: BlurEffect = BlurEffect.GAUSSIAN;
  @Trace blurTarget: BlurTarget = BlurTarget.FACE;

  // ====== 偏好(来自设置) ======
  @Trace emojiPalette: string[] = [];
  @Trace selectedFont: string = DEFAULT_FONT_MARKER;
  /** 是否允许自动布置表情时重复使用同一表情(来自设置，可在编辑页快捷切换)。 */
  @Trace allowEmojiRepeat: boolean = false;
  /** 已注册的自定义 emoji 字体族名(空串表示使用系统默认字体)。由页面注册字体后写入。 */
  @Trace emojiFontFamily: string = '';

  // ====== 交互/瞬时态 ======
  @Trace isProcessing: boolean = false;
  @Trace isExporting: boolean = false;
  @Trace isAddMode: boolean = false;
  @Trace selectedMaskId: string | null = null;
  /** 是否正在拖动滑块：用于预览期降级渲染(模糊用轻量占位)以保证流畅。 */
  @Trace isSliding: boolean = false;
  /** 待删除确认的遮挡 id(非空表示 UI 应弹出二次确认对话框)。 */
  @Trace pendingDeleteId: string = '';

  // 编辑草稿(确认才写回)
  @Trace editingEmoji: EmojiMask | null = null;
  @Trace editingBlur: BlurMask | null = null;
  @Trace editingId: string = '';
  @Trace editingIsNew: boolean = false;

  // 一次性提示(资源 key 或文案)，UI 显示后调用 consumeToast 清空
  @Trace toast: string = '';

  /** Ability 上下文(保存/分享需要)。 */
  private context: common.UIAbilityContext | null = null;

  private get container(): AppContainer {
    return AppContainer.instance();
  }

  /** 绑定上下文并从设置载入默认偏好。页面 aboutToAppear 调用。 */
  async attach(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    const repo = this.container.settingsRepo;
    this.emojiPalette = repo.getEmojiPalette();
    this.selectedFont = repo.getSelectedFont();
    this.allowEmojiRepeat = repo.getAllowEmojiRepeat();
    this.maskKind = repo.getDefaultMaskKind();
    this.blurEffect = repo.getDefaultBlurEffect();
    this.blurTarget = repo.getDefaultBlurTarget();
  }

  /** ====== 加载与检测 ====== */

  /** 从 uri 加载图片，随后自动检测并按当前模式生成遮挡。 */
  async loadFromUri(uri: string): Promise<void> {
    if (!uri) {
      return;
    }
    this.clear();
    this.isProcessing = true;
    const loadRes: Result<LoadedImage> = await this.container.loadImage.execute(uri);
    if (!loadRes.ok || !loadRes.value) {
      this.isProcessing = false;
      this.toast = 'msg_load_failed';
      Logger.error(EditorViewModel.TAG, 'load image failed', loadRes.error);
      return;
    }
    this.loaded = loadRes.value;
    this.aspectRatio = loadRes.value.aspectRatio;

    // 分块检测：按原生分辨率切块逐块检测再合并，突破系统检测器的整图下采样/数量限制。
    const detected: FaceDetection[] | null = await this.detectAllFaces(uri, loadRes.value);
    if (detected === null) {
      this.isProcessing = false;
      // 检测器内部已对"模型不可用"优雅降级为返回空；走到这里说明发生了意外错误。
      this.toast = 'msg_model_failed';
      return;
    }
    this.detections = detected;
    this.rebuildMasksForCurrentMode();
    if (this.detections.length === 0) {
      this.toast = 'msg_no_face';
    }
    this.isProcessing = false;
  }

  /**
   * 自适应细分人脸检测：系统检测器每次调用最多约返回 10 张脸；若某区域一次调用返回数
   * 达到阈值(说明被截断)，就把该区域切成带重叠的四块分别再检测，反复细分至不足阈值，
   * 最后把所有区域结果映射回原图坐标并 NMS 去重，用"多次调用"突破"单次数量上限"。
   * @returns 代理图坐标系下的检测结果；发生意外错误(无任何成功调用且无结果)返回 null。
   */
  private async detectAllFaces(uri: string, loaded: LoadedImage): Promise<FaceDetection[] | null> {
    let ow: number = 0;
    let oh: number = 0;
    try {
      const size: image.Size = await this.container.photoRepo.getImageSize(uri);
      ow = size.width;
      oh = size.height;
    } catch (e) {
      Logger.warn(EditorViewModel.TAG, 'get image size failed, fallback to proxy detect');
      const r: Result<FaceDetection[]> = await this.container.detectFaces.execute(loaded.proxy);
      return r.ok && r.value ? r.value : null;
    }
    if (ow <= 0 || oh <= 0) {
      const r: Result<FaceDetection[]> = await this.container.detectFaces.execute(loaded.proxy);
      return r.ok && r.value ? r.value : null;
    }

    const out: FaceDetection[] = [];
    const budget: DetectBudget = { calls: 0, anyOk: false };
    await this.detectRegion(uri, 0, 0, ow, oh, ow, oh, 0, out, budget);

    // 无任何成功调用且无结果：视为检测异常(与"检测到 0 张"区分)。
    if (out.length === 0 && !budget.anyOk) {
      return null;
    }
    const merged: FaceDetection[] = EditorViewModel.nms(out, AppConstants.DETECT_DEDUP_IOU);
    const k: number = ow > 0 ? loaded.proxyWidth / ow : 1;
    Logger.info(EditorViewModel.TAG,
      `adaptive detect: ${budget.calls} call(s), ${merged.length} face(s), origin ${ow}x${oh}`);
    if (Math.abs(k - 1) < 1e-3) {
      return merged;
    }
    return merged.map((d: FaceDetection): FaceDetection => EditorViewModel.scaleDetection(d, k));
  }

  /**
   * 递归检测一个原图矩形区域，把结果(映射回原图坐标)累加到 out。
   * 若该区域返回数达到阈值(疑似被截断)且可继续细分，则切四块(带重叠)递归。
   * @param rx/ry/rw/rh 区域(原图坐标)。 @param ow/oh 原图尺寸(用于裁剪子块)。
   */
  private async detectRegion(
    uri: string, rx: number, ry: number, rw: number, rh: number,
    ow: number, oh: number, depth: number, out: FaceDetection[], budget: DetectBudget
  ): Promise<void> {
    if (budget.calls >= AppConstants.DETECT_MAX_CALLS) {
      return;
    }
    // 退化区域(原生短边过小)：升采样也无意义，跳过。
    if (depth > 0 && Math.min(rw, rh) < AppConstants.DETECT_MIN_NATIVE) {
      return;
    }
    // 决定解码尺寸：大区域按 REGION_MAX 降采样限制内存；小区域升采样到 UPSCALE_TO，
    // 使其中小脸放大、越过系统检测器的最小人脸/输入尺寸限制。记录缩放以便坐标还原。
    const nativeLong: number = Math.max(rw, rh);
    let scale: number = 1;
    if (nativeLong > AppConstants.DETECT_REGION_MAX) {
      scale = AppConstants.DETECT_REGION_MAX / nativeLong;
    } else if (nativeLong < AppConstants.DETECT_UPSCALE_TO) {
      scale = AppConstants.DETECT_UPSCALE_TO / nativeLong;
    }
    const dw: number = Math.max(1, Math.round(rw * scale));
    const dh: number = Math.max(1, Math.round(rh * scale));

    budget.calls++;
    let faces: FaceDetection[] = [];
    let pm: image.PixelMap | null = null;
    try {
      pm = await this.container.photoRepo.decodeRegion(uri, rx, ry, rw, rh, dw, dh);
      const r: Result<FaceDetection[]> = await this.container.detectFaces.execute(pm);
      if (r.ok && r.value) {
        budget.anyOk = true;
        faces = r.value;
      }
    } catch (e) {
      Logger.warn(EditorViewModel.TAG, 'region detect failed');
    } finally {
      if (pm) {
        EditorViewModel.safeRelease(pm);
      }
    }

    // 解码区域坐标 → 原图坐标：加区域原点 + 乘回降采样系数。
    const sx: number = dw > 0 ? rw / dw : 1;
    const sy: number = dh > 0 ? rh / dh : 1;
    for (const d of faces) {
      out.push(EditorViewModel.mapDetection(d, rx, ry, sx, sy));
    }
    // 诊断：记录"零产出"块的解码尺寸，用于测定系统检测器的真实最小输入尺寸并据此调参。
    if (faces.length === 0) {
      Logger.info(EditorViewModel.TAG, `empty region ${dw}x${dh} (depth ${depth})`);
    }

    // 达到上限且仍可细分 → 切四块(带重叠)递归。
    const canSplit: boolean =
      depth < AppConstants.DETECT_MAX_DEPTH && Math.min(rw, rh) > AppConstants.DETECT_MIN_SPLIT;
    if (faces.length >= AppConstants.DETECT_SUBDIVIDE_THRESHOLD && canSplit) {
      const ov: number = AppConstants.DETECT_SPLIT_OVERLAP;
      const hw: number = rw / 2;
      const hh: number = rh / 2;
      const ex: number = hw * ov;
      const ey: number = hh * ov;
      const quads: number[][] = [
        [rx, ry, hw + ex, hh + ey],
        [rx + hw - ex, ry, hw + ex, hh + ey],
        [rx, ry + hh - ey, hw + ex, hh + ey],
        [rx + hw - ex, ry + hh - ey, hw + ex, hh + ey]
      ];
      for (const q of quads) {
        const qx: number = Math.max(0, Math.round(q[0]));
        const qy: number = Math.max(0, Math.round(q[1]));
        let qw: number = Math.round(q[2]);
        let qh: number = Math.round(q[3]);
        if (qx + qw > ow) {
          qw = ow - qx;
        }
        if (qy + qh > oh) {
          qh = oh - qy;
        }
        if (qw >= 1 && qh >= 1) {
          await this.detectRegion(uri, qx, qy, qw, qh, ow, oh, depth + 1, out, budget);
        }
      }
    }
  }

  /** NMS 去重：按分数降序，IoU 超阈值视为同一张脸，保留分数更高者。 */
  private static nms(list: FaceDetection[], iouThreshold: number): FaceDetection[] {
    const sorted: FaceDetection[] = list.slice().sort(
      (a: FaceDetection, b: FaceDetection): number => b.score - a.score
    );
    const keep: FaceDetection[] = [];
    for (const d of sorted) {
      let duplicate: boolean = false;
      for (const k of keep) {
        if (EditorViewModel.iou(d.box, k.box) > iouThreshold) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        keep.push(d);
      }
    }
    return keep;
  }

  /** 两个矩形的 IoU。 */
  private static iou(a: RectF, b: RectF): number {
    const x1: number = Math.max(a.left, b.left);
    const y1: number = Math.max(a.top, b.top);
    const x2: number = Math.min(a.right, b.right);
    const y2: number = Math.min(a.bottom, b.bottom);
    const inter: number = Math.max(0, x2 - x1) * Math.max(0, y2 - y1);
    const areaA: number = Math.max(0, a.width) * Math.max(0, a.height);
    const areaB: number = Math.max(0, b.width) * Math.max(0, b.height);
    const union: number = areaA + areaB - inter;
    return union <= 0 ? 0 : inter / union;
  }

  /** 把一次检测结果从"解码区域坐标"映射回"原图坐标"(加区域原点 + 乘降采样系数)。 */
  private static mapDetection(d: FaceDetection, ox: number, oy: number, sx: number, sy: number): FaceDetection {
    const b: RectF = d.box;
    const box: RectF = new RectF(ox + b.left * sx, oy + b.top * sy, ox + b.right * sx, oy + b.bottom * sy);
    const l: FaceLandmarks = d.landmarks;
    const lm: FaceLandmarks = new FaceLandmarks(
      new PointF(ox + l.leftEye.x * sx, oy + l.leftEye.y * sy),
      new PointF(ox + l.rightEye.x * sx, oy + l.rightEye.y * sy),
      new PointF(ox + l.nose.x * sx, oy + l.nose.y * sy),
      new PointF(ox + l.mouthLeft.x * sx, oy + l.mouthLeft.y * sy),
      new PointF(ox + l.mouthRight.x * sx, oy + l.mouthRight.y * sy)
    );
    return new FaceDetection(d.id, box, lm, d.score);
  }

  /** 按比例缩放一次检测结果的框与关键点(原图坐标 → 代理图坐标)。 */
  private static scaleDetection(d: FaceDetection, f: number): FaceDetection {
    const box: RectF = d.box.scaled(f);
    const l: FaceLandmarks = d.landmarks;
    const lm: FaceLandmarks = new FaceLandmarks(
      new PointF(l.leftEye.x * f, l.leftEye.y * f),
      new PointF(l.rightEye.x * f, l.rightEye.y * f),
      new PointF(l.nose.x * f, l.nose.y * f),
      new PointF(l.mouthLeft.x * f, l.mouthLeft.y * f),
      new PointF(l.mouthRight.x * f, l.mouthRight.y * f)
    );
    return new FaceDetection(d.id, box, lm, d.score);
  }

  /** 根据当前模式，由检测结果重建遮挡列表。 */
  private rebuildMasksForCurrentMode(): void {
    if (this.maskKind === MaskKind.EMOJI) {
      this.blurMasks = [];
      this.emojiMasks = this.container.placeEmoji.execute(this.detections, this.emojiPalette, this.allowEmojiRepeat);
    } else {
      this.emojiMasks = [];
      this.blurMasks = this.container.buildBlur.execute(this.detections, this.blurTarget);
    }
  }

  /**
   * 切换"允许表情重复"：持久化并即时重排(仅在表情模式且已加载图片时)。
   * 重排会覆盖当前自动/手动的表情遮挡(符合"切换即重排"的约定)。
   */
  async setAllowEmojiRepeat(allow: boolean): Promise<void> {
    if (this.allowEmojiRepeat === allow) {
      return;
    }
    this.allowEmojiRepeat = allow;
    await this.container.settingsRepo.setAllowEmojiRepeat(allow);
    if (this.loaded && this.maskKind === MaskKind.EMOJI) {
      this.cancelEditing();
      this.emojiMasks = this.container.placeEmoji.execute(this.detections, this.emojiPalette, this.allowEmojiRepeat);
    }
  }

  /** ====== 模式切换 ====== */

  setMaskKind(kind: MaskKind): void {
    if (this.maskKind === kind) {
      return;
    }
    this.maskKind = kind;
    this.cancelEditing();
    if (this.loaded) {
      this.rebuildMasksForCurrentMode();
    }
  }

  setBlurEffect(effect: BlurEffect): void {
    this.blurEffect = effect;
    // 仅改变视觉效果，不需重建区域。
  }

  setBlurTarget(target: BlurTarget): void {
    if (this.blurTarget === target) {
      return;
    }
    this.blurTarget = target;
    if (this.loaded && this.maskKind === MaskKind.BLUR) {
      this.blurMasks = this.container.buildBlur.execute(this.detections, target);
    }
  }

  /** ====== 新增 ====== */

  enterAddMode(): void {
    this.isAddMode = true;
  }

  exitAddMode(): void {
    this.isAddMode = false;
  }

  /**
   * 直接在图片中心添加一个指定 emoji 的遮挡并选中它（不弹调整面板）。
   * 用于底部调色板"点选即添加"。随后用户可拖动/点选微调。
   */
  addEmojiAtCenter(emoji: string): void {
    if (!this.loaded || this.maskKind !== MaskKind.EMOJI) {
      return;
    }
    const cx: number = this.loaded.proxyWidth / 2;
    const cy: number = this.loaded.proxyHeight / 2;
    const mask: EmojiMask = new EmojiMask(cx, cy, AppConstants.DEFAULT_EMOJI_DIAMETER, 0, emoji);
    this.emojiMasks = this.emojiMasks.concat([mask]);
    this.selectedMaskId = mask.id;
  }

  /**
   * 从一段文本(键盘输入/粘贴)中提取一个或多个 emoji 并加到图片中心，选中最后一个。
   * 多个 emoji 时以中心为基准横向轻微错开，避免完全重叠不便拖动。
   * @param text 用户输入的原始文本(可能含多个 emoji 或普通字符，普通字符会被过滤)。
   */
  addEmojisFromText(text: string): void {
    if (!this.loaded || this.maskKind !== MaskKind.EMOJI) {
      return;
    }
    const list: string[] = EmojiUtil.split(text);
    if (list.length === 0) {
      return;
    }
    const cx0: number = this.loaded.proxyWidth / 2;
    const cy0: number = this.loaded.proxyHeight / 2;
    const step: number = AppConstants.DEFAULT_EMOJI_DIAMETER * 0.35;
    const next: EmojiMask[] = this.emojiMasks.slice();
    let lastId: string = '';
    for (let i: number = 0; i < list.length; i++) {
      const cx: number = cx0 + (i - (list.length - 1) / 2) * step;
      const mask: EmojiMask = new EmojiMask(cx, cy0, AppConstants.DEFAULT_EMOJI_DIAMETER, 0, list[i]);
      next.push(mask);
      lastId = mask.id;
    }
    this.emojiMasks = next;
    this.selectedMaskId = lastId;
  }

  /** 在图片上点击新增遮挡(代理图坐标)。进入编辑草稿，确认后落地。 */
  addAtPoint(x: number, y: number): void {
    this.isAddMode = false;
    if (this.maskKind === MaskKind.EMOJI) {
      const emoji: string = this.randomEmoji();
      const d: number = AppConstants.DEFAULT_EMOJI_DIAMETER;
      this.editingEmoji = new EmojiMask(x, y, d, 0, emoji);
      this.editingBlur = null;
    } else {
      const s: number = AppConstants.DEFAULT_BLUR_SIZE;
      const rect: RectF = RectF.fromCenter(x, y, s, s);
      this.editingBlur = new BlurMask(rect, 0);
      this.editingEmoji = null;
    }
    this.editingId = '';
    this.editingIsNew = true;
    this.selectedMaskId = null;
  }

  /** ====== 选中并编辑已有遮挡 ====== */

  selectMask(id: string): void {
    this.selectedMaskId = id;
    if (this.maskKind === MaskKind.EMOJI) {
      const m: EmojiMask | undefined = this.emojiMasks.find((e: EmojiMask): boolean => e.id === id);
      if (m) {
        this.editingEmoji = m.clone();
        this.editingBlur = null;
        this.editingId = id;
        this.editingIsNew = false;
      }
    } else {
      const m: BlurMask | undefined = this.blurMasks.find((b: BlurMask): boolean => b.id === id);
      if (m) {
        this.editingBlur = m.clone();
        this.editingEmoji = null;
        this.editingId = id;
        this.editingIsNew = false;
      }
    }
  }

  /** ====== 编辑草稿更新 ====== */

  updateEditingEmojiChar(emoji: string): void {
    if (this.editingEmoji) {
      const c: EmojiMask = this.editingEmoji.clone();
      c.emoji = emoji;
      this.editingEmoji = c;
    }
  }

  updateEditingSizeFactor(factor: number): void {
    if (this.maskKind === MaskKind.EMOJI && this.editingEmoji) {
      this.editingEmoji = this.editingEmoji.withSizeFactor(factor);
    } else if (this.editingBlur) {
      this.editingBlur = this.editingBlur.withSizeFactor(factor);
    }
  }

  updateEditingAngle(angle: number): void {
    if (this.maskKind === MaskKind.EMOJI && this.editingEmoji) {
      const c: EmojiMask = this.editingEmoji.clone();
      c.angle = angle;
      this.editingEmoji = c;
    } else if (this.editingBlur) {
      const c: BlurMask = this.editingBlur.clone();
      c.angle = angle;
      this.editingBlur = c;
    }
  }

  /** 确认编辑：新增则加入列表，否则按 id 替换；emoji 为空视为删除。 */
  confirmEditing(): void {
    if (this.maskKind === MaskKind.EMOJI && this.editingEmoji) {
      const draft: EmojiMask = this.editingEmoji;
      if (draft.emoji.trim().length === 0) {
        if (!this.editingIsNew) {
          this.emojiMasks = this.emojiMasks.filter((e: EmojiMask): boolean => e.id !== this.editingId);
        }
      } else if (this.editingIsNew) {
        this.emojiMasks = this.emojiMasks.concat([draft]);
      } else {
        this.emojiMasks = this.emojiMasks.map(
          (e: EmojiMask): EmojiMask => (e.id === this.editingId ? draft : e)
        );
      }
    } else if (this.maskKind === MaskKind.BLUR && this.editingBlur) {
      const draft: BlurMask = this.editingBlur;
      if (this.editingIsNew) {
        this.blurMasks = this.blurMasks.concat([draft]);
      } else {
        this.blurMasks = this.blurMasks.map(
          (b: BlurMask): BlurMask => (b.id === this.editingId ? draft : b)
        );
      }
    }
    this.cancelEditing();
  }

  /** 取消编辑：清空所有草稿与选中。 */
  cancelEditing(): void {
    this.editingEmoji = null;
    this.editingBlur = null;
    this.editingId = '';
    this.editingIsNew = false;
    this.selectedMaskId = null;
    this.isSliding = false;
  }

  /** 删除指定遮挡。 */
  deleteMask(id: string): void {
    this.emojiMasks = this.emojiMasks.filter((e: EmojiMask): boolean => e.id !== id);
    this.blurMasks = this.blurMasks.filter((b: BlurMask): boolean => b.id !== id);
    if (this.selectedMaskId === id) {
      this.cancelEditing();
    }
  }

  /**
   * 按代理图坐标的位移拖动移动指定遮挡(直接更新列表对象并高亮选中)。
   * @param id 目标遮挡 id。
   * @param dx 代理图 X 位移。
   * @param dy 代理图 Y 位移。
   */
  moveMaskBy(id: string, dx: number, dy: number): void {
    if (this.maskKind === MaskKind.EMOJI) {
      this.emojiMasks = this.emojiMasks.map((e: EmojiMask): EmojiMask => {
        if (e.id !== id) {
          return e;
        }
        const c: EmojiMask = e.clone();
        c.centerX += dx;
        c.centerY += dy;
        return c;
      });
    } else {
      this.blurMasks = this.blurMasks.map((b: BlurMask): BlurMask => {
        if (b.id !== id) {
          return b;
        }
        const c: BlurMask = b.clone();
        c.rect = c.rect.translated(dx, dy);
        return c;
      });
    }
    this.selectedMaskId = id;
  }

  /**
   * 调整面板"删除"按钮：
   *  - 新增的草稿(尚未落地)直接丢弃，无需二次确认；
   *  - 已存在的遮挡走二次确认流程(设置 pendingDeleteId 由 UI 弹框)。
   */
  requestDeleteEditing(): void {
    if (this.editingIsNew || !this.editingId) {
      this.cancelEditing();
    } else {
      this.requestDelete(this.editingId);
    }
  }

  /**
   * 请求删除某遮挡(由长按或调整面板触发)，交由 UI 弹二次确认对话框。
   * @param id 目标遮挡 id。
   */
  requestDelete(id: string): void {
    if (id) {
      this.pendingDeleteId = id;
    }
  }

  /** UI 二次确认后真正删除待删遮挡。 */
  confirmPendingDelete(): void {
    const id: string = this.pendingDeleteId;
    this.pendingDeleteId = '';
    if (id) {
      this.deleteMask(id);
    }
  }

  /** UI 取消删除：清空待删标记。 */
  cancelPendingDelete(): void {
    this.pendingDeleteId = '';
  }

  /** ====== 导出 / 保存 / 分享 ====== */

  /**
   * 构造导出请求。编辑期不常驻全分辨率原图，这里按 uri 临时解码原图(渲染后由调用方释放)。
   * 解码失败返回 null。
   */
  private async buildExportRequest(): Promise<ExportRequest | null> {
    const l: LoadedImage | null = this.loaded;
    if (!l) {
      return null;
    }
    try {
      const original: image.PixelMap = await this.container.photoRepo.decode(l.uri);
      return {
        original,
        maskKind: this.maskKind,
        emojiMasks: this.emojiMasks,
        blurMasks: this.blurMasks,
        blurEffect: this.blurEffect,
        scaleToOriginal: l.scaleToOriginal,
        fontFamily: this.emojiFontFamily.length > 0 ? this.emojiFontFamily : undefined
      };
    } catch (e) {
      Logger.error(EditorViewModel.TAG, 'decode original for export failed', e as Error);
      return null;
    }
  }

  /**
   * 保存到相册。须由 UI 侧 SaveButton 安全控件在授权成功后调用：
   *   1) 先创建相册资源(消费一次性授权窗口)；
   *   2) 再做高清重渲染导出；
   *   3) 把结果写入该资源。
   * 顺序保证 createAsset 是授权后的首个敏感调用。
   */
  async save(): Promise<void> {
    const ctx: common.UIAbilityContext | null = this.context;
    if (!ctx || !this.loaded || this.isExporting) {
      return;
    }
    this.isExporting = true;
    // 1) 在授权窗口内首先创建相册资源。
    const assetRes: Result<string> = await this.container.saveImage.createAsset(ctx);
    if (!assetRes.ok || !assetRes.value) {
      this.isExporting = false;
      this.toast = 'msg_save_failed';
      Logger.error(EditorViewModel.TAG, 'create asset failed', assetRes.error);
      return;
    }
    // 2) 高清导出(按 uri 临时解码原图)。
    const req: ExportRequest | null = await this.buildExportRequest();
    if (!req) {
      this.isExporting = false;
      this.toast = 'msg_save_failed';
      return;
    }
    const exportRes: Result<image.PixelMap> = await this.container.exportImage.execute(req);
    // 原图已渲染完毕，立即释放，避免全分辨率原生内存停留。
    EditorViewModel.safeRelease(req.original);
    if (!exportRes.ok || !exportRes.value) {
      this.isExporting = false;
      this.toast = 'msg_save_failed';
      return;
    }
    // 3) 写入资源。
    const writeRes: Result<void> = await this.container.saveImage.write(assetRes.value, exportRes.value);
    EditorViewModel.safeRelease(exportRes.value);
    this.toast = writeRes.ok ? 'msg_save_success' : 'msg_save_failed';
    this.isExporting = false;
  }

  async share(): Promise<void> {
    const ctx: common.UIAbilityContext | null = this.context;
    if (!ctx || !this.loaded || this.isExporting) {
      return;
    }
    this.isExporting = true;
    const req: ExportRequest | null = await this.buildExportRequest();
    if (!req) {
      this.isExporting = false;
      this.toast = 'msg_share_failed';
      return;
    }
    const exportRes: Result<image.PixelMap> = await this.container.exportImage.execute(req);
    EditorViewModel.safeRelease(req.original);
    if (!exportRes.ok || !exportRes.value) {
      this.isExporting = false;
      this.toast = 'msg_share_failed';
      return;
    }
    const shareRes: Result<void> = await this.container.shareImage.execute(ctx, exportRes.value);
    EditorViewModel.safeRelease(exportRes.value);
    if (!shareRes.ok) {
      this.toast = 'msg_share_failed';
    }
    this.isExporting = false;
  }

  /** ====== 其它 ====== */

  /** 清空当前图片与遮挡(保留偏好)。 */
  clear(): void {
    this.loaded = null;
    this.aspectRatio = 1;
    this.detections = [];
    this.emojiMasks = [];
    this.blurMasks = [];
    this.isAddMode = false;
    this.pendingDeleteId = '';
    this.cancelEditing();
  }

  /** UI 消费一次性提示后调用，清空提示。 */
  consumeToast(): void {
    this.toast = '';
  }

  /**
   * 释放当前图片占用的原生 PixelMap 资源。页面销毁(aboutToDisappear)时调用，
   * 避免全分辨率原图等原生内存在多次进出编辑器后累积，导致再次解码大图时 OOM 崩溃。
   *
   * 释放的是"代理显示图"proxy。导出路径不依赖 proxy(它按 uri 另行临时解码全分辨率原图，
   * 见 buildExportRequest)，故即便导出进行中释放 proxy 也不会影响导出结果；因此这里
   * 无条件释放，避免"导出中离开页面"时 proxy 泄漏。
   */
  dispose(): void {
    const l: LoadedImage | null = this.loaded;
    this.loaded = null;
    this.detections = [];
    this.emojiMasks = [];
    this.blurMasks = [];
    if (l) {
      EditorViewModel.safeRelease(l.proxy);
    }
  }

  /** 安全释放一个 PixelMap：吞掉异常与异步拒绝，避免影响调用流程。 */
  private static safeRelease(pm: image.PixelMap | undefined | null): void {
    if (!pm) {
      return;
    }
    try {
      pm.release().catch((): void => {});
    } catch (e) {
      // 忽略：释放失败不影响功能。
    }
  }

  /** 设置"正在拖动滑块"状态：拖动中预览降级以保证流畅，松手后恢复高质量渲染。 */
  setSliding(sliding: boolean): void {
    if (this.isSliding !== sliding) {
      this.isSliding = sliding;
    }
  }

  /** 从调色板随机取一个 emoji。 */
  private randomEmoji(): string {
    if (this.emojiPalette.length === 0) {
      return '🙂';
    }
    const idx: number = Math.floor(Math.random() * this.emojiPalette.length);
    return this.emojiPalette[idx];
  }
}
