/**
 * MaskOverlay.ets
 * 分层：UI / 编辑器视图（Canvas 预览叠加层）
 *
 * 职责：把代理图与遮挡实时绘制到 Canvas，处理点击(新增/选中)与缩放/平移手势。
 *
 * 显示模型(对齐上游 EmojiFace)：
 *   - 图片始终按 contain "完整居中"显示：任意比例都不裁剪、不变形，留白处为画布背景；
 *   - 在 contain 基础上叠加用户手势：双指捏合缩放(userScale)、单指拖动平移(panX/panY)；
 *   - 所有遮挡(emoji/模糊)坐标都在"代理图"空间，绘制时统一施加同一仿射变换，
 *     因此遮挡会跟随图片一起缩放/平移，且 emoji 跟随人脸大小(diameter)与方向(angle)。
 *
 * 坐标变换(代理图 px → 画布 px)：screen = totalScale · proxy + totalOffset
 *   containScale = min(canvasW/pw, canvasH/ph)            // contain 适配
 *   baseOffset   = ((canvasW-pw·containScale)/2, …)        // 居中留白
 *   totalScale   = containScale · userScale
 *   totalOffset  = userScale·baseOffset + center·(1-userScale) + pan
 * 命中检测用其逆变换：proxy = (screen - totalOffset) / totalScale。
 *
 * 重绘时机：图片/遮挡/编辑草稿/效果/选中/手势变化时。手势进行中模糊降级为占位以保流畅。
 */
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { EditorViewModel } from '../../viewmodel/EditorViewModel';
import { EmojiMask, BlurMask } from '../../domain/model/Mask';
import { MaskKind } from '../../domain/model/MaskEnums';
import { MaskPainter } from '../../capability/imaging/MaskPainter';
import { PixelMapUtil, RgbaBuffer } from '../../capability/imaging/PixelMapUtil';
import { PointF, isPointInCircle, isPointInRotatedEllipse } from '../../domain/model/Geometry';
import { Logger } from '../../common/utils/Logger';

/** 仿射变换参数：screen = scale·proxy + (offX, offY)。 */
interface ViewTransform {
  scale: number;
  offX: number;
  offY: number;
}

/** 缩放上下限。 */
const MIN_USER_SCALE: number = 1;
const MAX_USER_SCALE: number = 6;

@ComponentV2
export struct MaskOverlay {
  @Param vm: EditorViewModel = new EditorViewModel();

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  @Local canvasW: number = 0;
  @Local canvasH: number = 0;
  /** 用户缩放系数(相对 contain 适配)，1 = 完整显示。 */
  @Local userScale: number = 1;
  /** 用户平移(画布 px)。 */
  @Local panX: number = 0;
  @Local panY: number = 0;

  private canvasReady: boolean = false;
  /** 代理图 RGBA 缓冲缓存(供模糊区域抽取)。 */
  private proxyBuf: RgbaBuffer | null = null;
  private cachedProxy: image.PixelMap | null = null;
  /** 重绘并发保护。 */
  private redrawing: boolean = false;
  private redrawDirty: boolean = false;
  /** 手势进行中标记：用于模糊降级占位，保证缩放/平移流畅。 */
  private gesturing: boolean = false;
  /** 手势起始基准。 */
  private pinchStartScale: number = 1;
  private panStartX: number = 0;
  private panStartY: number = 0;
  /** 单指拖动中的目标遮挡 id（空串表示拖动平移画布）。 */
  private dragId: string = '';
  /** 上一次拖动的累计位移(用于增量计算)。 */
  private lastDragOffsetX: number = 0;
  private lastDragOffsetY: number = 0;
  /**
   * 当前主题下的品牌色(选中环描边)与其半透明填充(模糊占位)。
   * Canvas 不能直接用 $r 资源色，故每次重绘前从 resourceManager 解析当前主题取值，
   * 保证深浅模式下选中态颜色与全局一致(深色 brand=#7C8AFF，浅色 brand=#5B6CFF)。
   */
  private brandStroke: string = '#5B6CFF';
  private brandFill: string = 'rgba(91,108,255,0.35)';

  /** 监听影响绘制的状态变化，触发重绘。图片切换时复位视图。 */
  @Monitor('vm.loaded')
  onImageChange(): void {
    this.userScale = 1;
    this.panX = 0;
    this.panY = 0;
    this.redraw();
  }

  @Monitor('vm.emojiMasks', 'vm.blurMasks', 'vm.editingEmoji', 'vm.editingBlur', 'vm.blurEffect', 'vm.maskKind', 'vm.selectedMaskId', 'vm.isSliding')
  onStateChange(): void {
    this.redraw();
  }

  /** 组件销毁：停止后续重绘并丢弃对(即将被释放的)代理图缓冲的引用，避免 use-after-free。 */
  aboutToDisappear(): void {
    this.canvasReady = false;
    this.proxyBuf = null;
    this.cachedProxy = null;
  }

  /** 计算当前 contain 适配的基础量。 */
  private fitBase(): ViewTransform {
    const pw: number = this.proxyBuf ? this.proxyBuf.width : 0;
    const ph: number = this.proxyBuf ? this.proxyBuf.height : 0;
    if (pw <= 0 || ph <= 0 || this.canvasW <= 0 || this.canvasH <= 0) {
      return { scale: 1, offX: 0, offY: 0 };
    }
    const containScale: number = Math.min(this.canvasW / pw, this.canvasH / ph);
    const offX: number = (this.canvasW - pw * containScale) / 2;
    const offY: number = (this.canvasH - ph * containScale) / 2;
    return { scale: containScale, offX, offY };
  }

  /** 计算叠加用户缩放/平移后的总变换(代理图 px → 画布 px)。 */
  private computeView(): ViewTransform {
    const base: ViewTransform = this.fitBase();
    const cx: number = this.canvasW / 2;
    const cy: number = this.canvasH / 2;
    const scale: number = base.scale * this.userScale;
    const offX: number = this.userScale * base.offX + cx * (1 - this.userScale) + this.panX;
    const offY: number = this.userScale * base.offY + cy * (1 - this.userScale) + this.panY;
    return { scale, offX, offY };
  }

  /** 把画布点击坐标(vp)换算为代理图坐标(px)。 */
  private toProxyPoint(x: number, y: number): PointF {
    const t: ViewTransform = this.computeView();
    if (t.scale <= 0) {
      return new PointF(x, y);
    }
    return new PointF((x - t.offX) / t.scale, (y - t.offY) / t.scale);
  }

  /** 限制平移范围：图片最多移出画布一半，避免完全移走。 */
  private clampPan(): void {
    const base: ViewTransform = this.fitBase();
    const pw: number = this.proxyBuf ? this.proxyBuf.width : 0;
    const ph: number = this.proxyBuf ? this.proxyBuf.height : 0;
    const scaledW: number = pw * base.scale * this.userScale;
    const scaledH: number = ph * base.scale * this.userScale;
    const maxX: number = Math.max(0, scaledW / 2);
    const maxY: number = Math.max(0, scaledH / 2);
    this.panX = Math.min(maxX, Math.max(-maxX, this.panX));
    this.panY = Math.min(maxY, Math.max(-maxY, this.panY));
  }

  private async ensureProxyBuffer(): Promise<void> {
    const loaded = this.vm.loaded;
    if (!loaded) {
      this.proxyBuf = null;
      this.cachedProxy = null;
      return;
    }
    if (this.cachedProxy === loaded.proxy && this.proxyBuf) {
      return;
    }
    this.proxyBuf = await PixelMapUtil.readRgba(loaded.proxy);
    this.cachedProxy = loaded.proxy;
  }

  /** 合并固定列表与编辑草稿，得到用于渲染的 emoji 列表。 */
  private emojisToRender(): EmojiMask[] {
    const list: EmojiMask[] = this.vm.emojiMasks.slice();
    const draft: EmojiMask | null = this.vm.editingEmoji;
    if (draft) {
      const idx: number = list.findIndex((e: EmojiMask): boolean => e.id === draft.id);
      if (idx >= 0) {
        list[idx] = draft;
      } else {
        list.push(draft);
      }
    }
    return list;
  }

  private blursToRender(): BlurMask[] {
    const list: BlurMask[] = this.vm.blurMasks.slice();
    const draft: BlurMask | null = this.vm.editingBlur;
    if (draft) {
      const idx: number = list.findIndex((b: BlurMask): boolean => b.id === draft.id);
      if (idx >= 0) {
        list[idx] = draft;
      } else {
        list.push(draft);
      }
    }
    return list;
  }

  /** 重新绘制整个画布(带并发保护)。 */
  private async redraw(): Promise<void> {
    if (this.redrawing) {
      this.redrawDirty = true;
      return;
    }
    this.redrawing = true;
    try {
      await this.doRedraw();
    } catch (e) {
      // 绘制失败不得向上抛出：redraw 由 @Monitor/手势回调以"游离 Promise"方式调用，
      // 未捕获的拒绝会升级为应用级崩溃。这里统一兜底记录。
      Logger.error('MaskOverlay', 'redraw failed', e as Error);
    } finally {
      this.redrawing = false;
      if (this.redrawDirty) {
        this.redrawDirty = false;
        this.redraw();
      }
    }
  }

  /** 实际绘制逻辑。 */
  private async doRedraw(): Promise<void> {
    if (!this.canvasReady || this.canvasW <= 0 || this.canvasH <= 0) {
      return;
    }
    this.resolveBrandColor();
    await this.ensureProxyBuffer();
    const loaded = this.vm.loaded;
    this.ctx.clearRect(0, 0, this.canvasW, this.canvasH);
    if (!loaded || !this.proxyBuf) {
      return;
    }
    const pw: number = this.proxyBuf.width;
    const ph: number = this.proxyBuf.height;
    const t: ViewTransform = this.computeView();

    this.ctx.save();
    this.ctx.translate(t.offX, t.offY);
    this.ctx.scale(t.scale, t.scale);

    // 1) 基图。
    this.ctx.drawImage(loaded.proxy, 0, 0, pw, ph);

    // 2) 遮挡(与基图同一变换栈，自动跟随缩放/平移)。
    try {
      if (this.vm.maskKind === MaskKind.EMOJI) {
        for (const m of this.emojisToRender()) {
          MaskPainter.paintEmoji(this.ctx, m, this.vm.emojiFontFamily);
        }
      } else if (this.vm.isSliding || this.gesturing) {
        // 拖动滑块/手势变换时：用轻量椭圆占位替代昂贵像素算法，保证流畅。
        for (const b of this.blursToRender()) {
          this.drawBlurPlaceholder(b);
        }
      } else {
        const buf: RgbaBuffer = this.proxyBuf;
        for (const b of this.blursToRender()) {
          await MaskPainter.paintBlur(this.ctx, b, buf, this.vm.blurEffect);
        }
      }
    } catch (e) {
      Logger.error('MaskOverlay', 'paint failed', e as Error);
    }

    // 3) 选中态高亮(同变换栈内，线宽除以 scale 保持视觉粗细)。
    this.drawSelectionRing(t.scale);
    this.ctx.restore();
  }

  /** 从资源系统按当前主题解析品牌色，更新 Canvas 描边/填充用色串。 */
  private resolveBrandColor(): void {
    try {
      const host: common.Context | undefined = this.getUIContext().getHostContext() as common.Context | undefined;
      if (host) {
        const argb: number = host.resourceManager.getColorByNameSync('brand');
        const r: number = (argb >> 16) & 0xff;
        const g: number = (argb >> 8) & 0xff;
        const b: number = argb & 0xff;
        this.brandStroke = `rgb(${r},${g},${b})`;
        this.brandFill = `rgba(${r},${g},${b},0.35)`;
      }
    } catch (e) {
      // 解析失败时保留默认浅色品牌色。
      Logger.warn('MaskOverlay', 'resolve brand color failed');
    }
  }

  /** 手势变换时的轻量模糊占位：半透明旋转椭圆(代理坐标系)。 */
  private drawBlurPlaceholder(b: BlurMask): void {
    this.ctx.save();
    this.ctx.translate(b.rect.centerX, b.rect.centerY);
    this.ctx.rotate((b.angle * Math.PI) / 180);
    this.ctx.beginPath();
    this.ctx.ellipse(0, 0, b.rect.width / 2, b.rect.height / 2, 0, 0, Math.PI * 2);
    this.ctx.fillStyle = this.brandFill;
    this.ctx.fill();
    this.ctx.restore();
  }

  /** 给选中/编辑中的遮挡画一个品牌色描边环(代理坐标系，线宽按 scale 反算)。 */
  private drawSelectionRing(scale: number): void {
    const id: string = this.vm.editingId || (this.vm.selectedMaskId ?? '');
    if (!id || scale <= 0) {
      return;
    }
    this.ctx.save();
    this.ctx.strokeStyle = this.brandStroke;
    this.ctx.lineWidth = 3 / scale;
    if (this.vm.maskKind === MaskKind.EMOJI) {
      const m: EmojiMask | undefined = this.emojisToRender().find((e: EmojiMask): boolean => e.id === id);
      if (m) {
        this.ctx.beginPath();
        this.ctx.arc(m.centerX, m.centerY, m.diameter / 2, 0, Math.PI * 2);
        this.ctx.stroke();
      }
    } else {
      const b: BlurMask | undefined = this.blursToRender().find((x: BlurMask): boolean => x.id === id);
      if (b) {
        this.ctx.translate(b.rect.centerX, b.rect.centerY);
        this.ctx.rotate((b.angle * Math.PI) / 180);
        this.ctx.beginPath();
        this.ctx.ellipse(0, 0, b.rect.width / 2, b.rect.height / 2, 0, 0, Math.PI * 2);
        this.ctx.stroke();
      }
    }
    this.ctx.restore();
  }

  /** 命中检测：返回点 p(代理坐标)命中的遮挡 id，从上层往下找；无命中返回空串。 */
  private hitTestMask(p: PointF): string {
    if (this.vm.maskKind === MaskKind.EMOJI) {
      const list: EmojiMask[] = this.vm.emojiMasks;
      for (let i: number = list.length - 1; i >= 0; i--) {
        const m: EmojiMask = list[i];
        if (isPointInCircle(p, m.centerX, m.centerY, m.diameter)) {
          return m.id;
        }
      }
    } else {
      const list: BlurMask[] = this.vm.blurMasks;
      for (let i: number = list.length - 1; i >= 0; i--) {
        const b: BlurMask = list[i];
        if (isPointInRotatedEllipse(p, b.rect, b.angle)) {
          return b.id;
        }
      }
    }
    return '';
  }

  /** 处理画布点击：新增模式→新增；否则命中检测选中(打开调整面板)。 */
  private handleTap(x: number, y: number): void {
    if (!this.vm.loaded) {
      return;
    }
    const p: PointF = this.toProxyPoint(x, y);
    if (this.vm.isAddMode) {
      this.vm.addAtPoint(p.x, p.y);
      return;
    }
    const id: string = this.hitTestMask(p);
    if (id) {
      this.vm.selectMask(id);
    }
  }

  build() {
    Canvas(this.ctx)
      .width('100%')
      .height('100%')
      .onReady(() => {
        this.canvasReady = true;
        this.redraw();
      })
      .onAreaChange((_o: Area, n: Area) => {
        this.canvasW = n.width as number;
        this.canvasH = n.height as number;
        this.redraw();
      })
      .onClick((e: ClickEvent) => {
        this.handleTap(e.x, e.y);
      })
      .gesture(
        GestureGroup(GestureMode.Parallel,
          // 长按遮挡：请求删除(由页面弹二次确认对话框)。
          LongPressGesture({ fingers: 1, repeat: false, duration: 500 })
            .onAction((event: GestureEvent) => {
              if (!this.vm.loaded || this.vm.isAddMode) {
                return;
              }
              const fingers: FingerInfo[] = event.fingerList;
              if (fingers.length > 0) {
                const f: FingerInfo = fingers[0];
                const p: PointF = this.toProxyPoint(f.localX, f.localY);
                const id: string = this.hitTestMask(p);
                if (id) {
                  this.vm.requestDelete(id);
                }
              }
            }),
          // 双指捏合缩放(围绕画布中心)。
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.gesturing = true;
              this.pinchStartScale = this.userScale;
            })
            .onActionUpdate((event: GestureEvent) => {
              const next: number = this.pinchStartScale * event.scale;
              this.userScale = Math.min(MAX_USER_SCALE, Math.max(MIN_USER_SCALE, next));
              this.clampPan();
              this.redraw();
            })
            .onActionEnd(() => {
              this.gesturing = false;
              if (this.userScale <= MIN_USER_SCALE + 0.001) {
                this.userScale = 1;
                this.panX = 0;
                this.panY = 0;
              }
              this.redraw();
            }),
          // 单指拖动：起点在某遮挡上→移动该遮挡；否则(放大后)平移画布。
          PanGesture({ fingers: 1 })
            .onActionStart((event: GestureEvent) => {
              this.gesturing = true;
              this.panStartX = this.panX;
              this.panStartY = this.panY;
              this.lastDragOffsetX = 0;
              this.lastDragOffsetY = 0;
              this.dragId = '';
              const fingers: FingerInfo[] = event.fingerList;
              if (this.vm.loaded && !this.vm.isAddMode && fingers.length > 0) {
                const f: FingerInfo = fingers[0];
                const p: PointF = this.toProxyPoint(f.localX, f.localY);
                this.dragId = this.hitTestMask(p);
              }
            })
            .onActionUpdate((event: GestureEvent) => {
              if (this.dragId) {
                // 移动遮挡：屏幕位移增量 / totalScale = 代理图位移。
                const t: ViewTransform = this.computeView();
                const dxScreen: number = event.offsetX - this.lastDragOffsetX;
                const dyScreen: number = event.offsetY - this.lastDragOffsetY;
                this.lastDragOffsetX = event.offsetX;
                this.lastDragOffsetY = event.offsetY;
                if (t.scale > 0) {
                  this.vm.moveMaskBy(this.dragId, dxScreen / t.scale, dyScreen / t.scale);
                }
              } else if (this.userScale > 1) {
                this.panX = this.panStartX + event.offsetX;
                this.panY = this.panStartY + event.offsetY;
                this.clampPan();
                this.redraw();
              }
            })
            .onActionEnd(() => {
              this.gesturing = false;
              this.dragId = '';
              this.redraw();
            })
        )
      )
  }
}
