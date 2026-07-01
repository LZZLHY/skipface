/**
 * EditorPage.ets
 * 分层：UI / 页面（编辑器，自适应单/双栏）
 *
 * 职责：编辑主界面。顶部导航(返回/标题/分享/保存)，中部 Canvas 预览(MaskOverlay)，
 *       底部操作坞(手机)或右侧属性检查器(平板/2in1)。编辑遮挡时弹出半模态调整面板。
 *
 * 一多：依据断点(@StorageProp)在 sm 用底部坞、md/lg 用右侧 Inspector。
 */
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { EditorViewModel } from '../viewmodel/EditorViewModel';
import { MaskKind, BlurEffect, BlurTarget } from '../domain/model/MaskEnums';
import { BreakpointModel } from '../common/breakpoint/BreakpointModel';
import { WidthBreakpoint } from '../common/breakpoint/BreakpointType';
import { SegmentedControl, SegItem } from '../components/SegmentedControl';
import { MaskOverlay } from '../view/editor/MaskOverlay';
import { AdjustSheet } from '../view/editor/AdjustSheet';
import { SafeAreaModel } from '../common/safearea/SafeAreaModel';
import { DEFAULT_FONT_MARKER } from '../data/settings/SettingsRepository';
import { Logger } from '../common/utils/Logger';

/** 自定义 emoji 字体注册时使用的固定族名。 */
const CUSTOM_EMOJI_FONT_FAMILY: string = 'skipface_emoji_font';

@ComponentV2
export struct EditorPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  /** 待加载图片 uri(路由参数)。 */
  @Param uri: string = '';
  @Local vm: EditorViewModel = new EditorViewModel();
  @Local sheetShown: boolean = false;
  @Local bpModel: BreakpointModel = BreakpointModel.instance();
  /** 系统安全区内边距(沉浸式布局下用于避让状态栏/手势条)。 */
  @Local safe: SafeAreaModel = SafeAreaModel.instance();
  /** 是否显示"键盘输入表情"浮层(临时功能：表情模式下点 + 调出键盘输入表情)。 */
  @Local emojiInputShown: boolean = false;
  /** 表情输入草稿(非响应式，避免 onChange 改 @Local 触发重渲染导致输入被回滚)。 */
  private emojiInputDraft: string = '';

  private modeOptions: SegItem[] = [
    { label: $r('app.string.mode_emoji') },
    { label: $r('app.string.mode_blur') }
  ];
  private effectOptions: SegItem[] = [
    { label: $r('app.string.effect_gaussian') },
    { label: $r('app.string.effect_pixelate') },
    { label: $r('app.string.effect_halftone') }
  ];
  private targetOptions: SegItem[] = [
    { label: $r('app.string.target_face') },
    { label: $r('app.string.target_eyes') }
  ];

  async aboutToAppear(): Promise<void> {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await this.vm.attach(ctx);
    this.registerSelectedFont();
    await this.vm.loadFromUri(this.uri);
  }

  /** 离开编辑器(返回首页)时释放图片原生资源，避免多次进出累积内存导致再选图崩溃。 */
  aboutToDisappear(): void {
    this.vm.dispose();
  }

  /** 注册用户选择的自定义字体并把族名写入 ViewModel(供 emoji 绘制使用)。 */
  private registerSelectedFont(): void {
    const path: string = this.vm.selectedFont;
    if (!path || path === DEFAULT_FONT_MARKER) {
      this.vm.emojiFontFamily = '';
      return;
    }
    try {
      this.getUIContext().getFont().registerFont({
        familyName: CUSTOM_EMOJI_FONT_FAMILY,
        familySrc: path
      });
      this.vm.emojiFontFamily = CUSTOM_EMOJI_FONT_FAMILY;
    } catch (e) {
      this.vm.emojiFontFamily = '';
      Logger.warn('EditorPage', 'register custom font failed');
    }
  }

  /** 编辑草稿出现/消失时同步底部面板显隐。 */
  @Monitor('vm.editingEmoji', 'vm.editingBlur')
  onEditingChange(): void {
    this.sheetShown = this.vm.editingEmoji !== null || this.vm.editingBlur !== null;
  }

  /** 一次性提示。 */
  @Monitor('vm.toast')
  onToast(): void {
    const key: string = this.vm.toast;
    if (!key) {
      return;
    }
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const msg: string = ctx.resourceManager.getStringByNameSync(key);
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (e) {
      // key 不是资源名(如动态错误信息)：直接作为文本展示。
      this.getUIContext().getPromptAction().showToast({ message: key, duration: 3500 });
    }
    this.vm.consumeToast();
  }

  /** 待删除确认：弹出二次确认对话框，确认后删除，取消则保留。 */
  @Monitor('vm.pendingDeleteId')
  onPendingDelete(): void {
    if (!this.vm.pendingDeleteId) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: $r('app.string.delete_dialog_title'),
      message: $r('app.string.delete_dialog_msg'),
      buttons: [
        { text: $r('app.string.action_cancel'), color: $r('app.color.text_secondary') },
        { text: $r('app.string.action_delete'), color: $r('app.color.danger') }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse): void => {
      if (res.index === 1) {
        this.vm.confirmPendingDelete();
      } else {
        this.vm.cancelPendingDelete();
      }
    }).catch((): void => {
      this.vm.cancelPendingDelete();
    });
  }

  @Builder
  adjustBuilder() {
    AdjustSheet({ vm: this.vm })
  }

  build() {
    Stack() {
      Column() {
        this.topNav()
        if (this.bpModel.current === WidthBreakpoint.LG || this.bpModel.current === WidthBreakpoint.MD) {
          // 双栏：画布 + 右侧检查器
          Row() {
            this.canvasArea()
            this.inspector()
          }
          .width('100%').layoutWeight(1)
        } else {
          // 单栏：画布 + 底部操作坞
          Column() {
            this.canvasArea()
            this.bottomDock()
          }
          .width('100%').layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.editor_canvas'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet(this.bpModel.current === WidthBreakpoint.SM && this.sheetShown, this.adjustBuilder(), {
        detents: [SheetSize.MEDIUM, SheetSize.LARGE],
        preferType: SheetType.BOTTOM,
        backgroundColor: $r('app.color.surface'),
        showClose: false,
        onWillDismiss: () => {
          this.vm.cancelEditing();
          this.sheetShown = false;
        }
      })

      if (this.emojiInputShown) {
        this.emojiInputOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  /** 提交"键盘输入表情"：解析输入文本，把其中的 emoji 加到画面中心，并关闭浮层。 */
  private commitEmojiInput(): void {
    this.vm.addEmojisFromText(this.emojiInputDraft);
    this.emojiInputDraft = '';
    this.emojiInputShown = false;
  }

  /** 关闭"键盘输入表情"浮层(取消)。 */
  private dismissEmojiInput(): void {
    this.emojiInputDraft = '';
    this.emojiInputShown = false;
  }

  /**
   * 键盘输入表情浮层(临时功能)：半透明遮罩 + 居中卡片。
   * 卡片内的 TextInput 自动获焦弹出系统键盘，用户切到表情面板输入后点"添加"。
   */
  @Builder
  emojiInputOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.dismissEmojiInput())

      Column() {
        Text($r('app.string.emoji_input_title'))
          .fontSize($r('app.float.font_headline'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        TextInput({ text: this.emojiInputDraft, placeholder: $r('app.string.emoji_input_hint') })
          .defaultFocus(true)
          .height(48)
          .margin({ top: 14 })
          .backgroundColor($r('app.color.surface_2'))
          .onChange((v: string) => { this.emojiInputDraft = v; })
          .onSubmit(() => this.commitEmojiInput())

        Row() {
          Button({ type: ButtonType.Capsule }) {
            Text($r('app.string.action_cancel')).fontSize($r('app.float.font_body')).fontColor($r('app.color.text_primary'))
          }
          .layoutWeight(1).height(46).backgroundColor($r('app.color.surface_2'))
          .onClick(() => this.dismissEmojiInput())

          Button({ type: ButtonType.Capsule }) {
            Text($r('app.string.action_add')).fontSize($r('app.float.font_body')).fontColor($r('app.color.on_brand'))
          }
          .layoutWeight(1).height(46).backgroundColor($r('app.color.brand')).margin({ left: 12 })
          .onClick(() => this.commitEmojiInput())
        }
        .width('100%').margin({ top: 18 })
      }
      .width('82%')
      .padding(20)
      .borderRadius($r('app.float.radius_l'))
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
    .height('100%')
  }

  /** 顶部导航。标题用 Stack 居中(相对全屏)，左右控件叠加其上，避免左右宽度不等导致标题偏移。 */
  @Builder
  topNav() {
    Stack() {
      Text($r('app.string.editor_title'))
        .fontSize($r('app.float.font_headline'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '50%' })

      Row() {
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(26).fontColor([$r('app.color.text_primary')])
        }
        .width(40).height(40).backgroundColor(Color.Transparent)
        .onClick(() => this.pathStack.pop())

        Blank()

        Row() {
          Button({ type: ButtonType.Capsule, stateEffect: true }) {
            Text($r('app.string.action_share')).fontSize($r('app.float.font_caption')).fontColor($r('app.color.text_primary'))
          }
          .height(36).backgroundColor($r('app.color.surface_2')).padding({ left: 14, right: 14 })
          .enabled(!this.vm.isExporting)
          .onClick(() => this.vm.share())

          // 保存：使用 SaveButton 安全控件，点击即获临时相册写入授权(免静态权限)。
          // SaveButton 为安全控件，不支持直接链式 margin，故用容器承载外边距。
          Row() {
            SaveButton({ icon: SaveIconStyle.FULL_FILLED, text: SaveDescription.SAVE_IMAGE, buttonType: ButtonType.Capsule })
              .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => {
                if (this.vm.isExporting) {
                  return;
                }
                if (result === SaveButtonOnClickResult.SUCCESS) {
                  this.vm.save();
                } else {
                  this.vm.toast = 'msg_save_failed';
                }
              })
          }
          .margin({ left: 6 })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%').height(52 + this.safe.top).padding({ left: 12, right: 12, top: this.safe.top })
  }

  /** 画布区域：Canvas 填满可用空间，内部按 contain 居中完整显示并支持缩放/平移。 */
  @Builder
  canvasArea() {
    Stack() {
      MaskOverlay({ vm: this.vm })
        .width('100%')
        .height('100%')

      if (this.vm.isProcessing) {
        Column() {
          LoadingProgress().width(48).height(48).color($r('app.color.brand'))
          Text($r('app.string.msg_detecting'))
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 8 })
        }
      }

      // 空/错误态：未加载出图片且非加载中(如解码失败)，给出明确占位而非纯黑画布。
      if (!this.vm.loaded && !this.vm.isProcessing) {
        Column() {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(40)
            .fontColor([$r('app.color.text_tertiary')])
          Text($r('app.string.editor_empty'))
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 10 })
            .textAlign(TextAlign.Center)
        }
        .padding({ left: 32, right: 32 })
      }

      if (this.vm.isAddMode) {
        Column() {
          Text($r('app.string.action_add'))
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.on_brand'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .borderRadius(14)
            .backgroundColor($r('app.color.brand'))
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Start).alignItems(HorizontalAlign.Center)
        .padding({ top: 12 })
      }
    }
    .layoutWeight(1)
    .width('100%')
    .padding(16)
    .alignContent(Alignment.Center)
  }

  /** 底部操作坞(手机)。 */
  @Builder
  bottomDock() {
    Column() {
      SegmentedControl({
        options: this.modeOptions,
        selected: this.vm.maskKind as number,
        onSelect: (i: number): void => { this.vm.setMaskKind(i as MaskKind); }
      })
      .margin({ bottom: 16 })

      if (this.vm.maskKind === MaskKind.EMOJI) {
        this.emojiTools()
      } else {
        this.blurTools()
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: this.safe.bottom + 28 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius({ topLeft: 24, topRight: 24 })
    .shadow({ radius: 16, color: '#0F000000', offsetX: 0, offsetY: -2 })
    // 让操作坞的背景延伸进底部手势安全区，避免安全区与坞底出现色差接缝。
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  /** 右侧属性检查器(平板/2in1)。编辑遮挡时内嵌调节面板，避免大屏使用底部弹层。 */
  @Builder
  inspector() {
    Column() {
      if (this.vm.editingEmoji !== null || this.vm.editingBlur !== null) {
        // 大屏：选中/新增遮挡时，调节面板内嵌在右侧检查器中(可滚动以适配较矮窗口)。
        Scroll() {
          AdjustSheet({ vm: this.vm })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
      } else {
        Scroll() {
          Column() {
            SegmentedControl({
              options: this.modeOptions,
              selected: this.vm.maskKind as number,
              fill: true,
              onSelect: (i: number): void => { this.vm.setMaskKind(i as MaskKind); }
            })
            .width('100%')
            .margin({ bottom: 20 })

            if (this.vm.maskKind === MaskKind.EMOJI) {
              this.emojiTools()
            } else {
              this.blurTools()
            }
          }
          .width('100%')
          .padding(20)
        }
        .layoutWeight(1)
        .align(Alignment.Top)
      }
    }
    .width(320)
    .height('100%')
    .backgroundColor($r('app.color.surface'))
  }

  /** Emoji 工具：允许重复开关 + 调色板横向滚动 + 添加。 */
  @Builder
  emojiTools() {
    Column() {
      // 快捷开关：允许表情重复（与设置项同一持久化状态，切换即重排）。
      Row() {
        Text($r('app.string.emoji_repeat_toggle'))
          .fontSize($r('app.float.font_caption'))
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.vm.allowEmojiRepeat })
          .width(46).height(28)
          .selectedColor($r('app.color.brand'))
          .onChange((v: boolean): void => { this.vm.setAllowEmojiRepeat(v); })
      }
      .width('100%').alignItems(VerticalAlign.Center).margin({ bottom: 10 })

      Row() {
        List({ space: 10 }) {
          ForEach(this.vm.emojiPalette, (e: string) => {
            ListItem() {
              Text(e)
                .fontSize(28)
                .width(52).height(52)
                .textAlign(TextAlign.Center)
                .borderRadius(16)
                .backgroundColor($r('app.color.surface_2'))
                .onClick(() => this.vm.addEmojiAtCenter(e))
            }
          }, (e: string, i: number) => `${i}_${e}`)
        }
        .listDirection(Axis.Horizontal)
        .layoutWeight(1)
        .height(52)

        Button({ type: ButtonType.Normal, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(26).fontColor([$r('app.color.brand')])
        }
        .width(52).height(52).borderRadius(16)
        .backgroundColor($r('app.color.brand_soft'))
        .borderWidth(1.5).borderColor($r('app.color.brand'))
        .margin({ left: 10 })
        .onClick(() => {
          // 临时：表情模式下点 + 调出键盘输入表情(而非进入点击画布添加模式)。
          this.emojiInputDraft = '';
          this.emojiInputShown = true;
        })
      }
      .width('100%').alignItems(VerticalAlign.Center)
    }
    .width('100%')
  }

  /** 模糊工具：效果芯片 + 目标 + 添加。 */
  @Builder
  blurTools() {
    Column() {
      Row() {
        ForEach(this.effectOptions, (opt: SegItem, idx: number) => {
          Column() {
            Text(opt.label)
              .fontSize($r('app.float.font_label'))
              .fontWeight(this.vm.blurEffect === idx ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(this.vm.blurEffect === idx ? $r('app.color.brand') : $r('app.color.text_secondary'))
          }
          .layoutWeight(1).height(50).justifyContent(FlexAlign.Center)
          .borderRadius(16)
          .backgroundColor(this.vm.blurEffect === idx ? $r('app.color.brand_soft') : $r('app.color.surface_2'))
          .borderWidth(this.vm.blurEffect === idx ? 1.5 : 0)
          .borderColor($r('app.color.brand'))
          .margin({ right: idx < this.effectOptions.length - 1 ? 10 : 0 })
          .onClick(() => this.vm.setBlurEffect(idx as BlurEffect))
        }, (opt: SegItem, idx: number) => `${idx}`)
      }
      .width('100%')

      Row() {
        Text($r('app.string.blur_target'))
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        SegmentedControl({
          options: this.targetOptions,
          selected: this.vm.blurTarget as number,
          onSelect: (i: number): void => { this.vm.setBlurTarget(i as BlurTarget); }
        })
      }
      .width('100%').margin({ top: 14 }).alignItems(VerticalAlign.Center)

      Button({ type: ButtonType.Capsule, stateEffect: true }) {
        Row() {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(20).fontColor([$r('app.color.brand')]).margin({ right: 6 })
          Text($r('app.string.action_add')).fontSize($r('app.float.font_caption')).fontColor($r('app.color.brand'))
        }
      }
      .height(44).backgroundColor($r('app.color.brand_soft')).margin({ top: 14 })
      .onClick(() => this.vm.enterAddMode())
    }
    .width('100%')
  }
}
