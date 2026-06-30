/**
 * AdjustSheet.ets
 * 分层：UI / 编辑器视图（调整面板内容）
 *
 * 职责：编辑选中/新增遮挡的半模态内容：Emoji 选择(仅表情模式) + 大小/角度滑块 + 取消/完成/删除。
 *       值实时回填(由 vm 的编辑草稿计算)。绑定方式由父级通过 bindSheet 提供。
 */
import { EditorViewModel } from '../../viewmodel/EditorViewModel';
import { MaskKind } from '../../domain/model/MaskEnums';
import { AppConstants } from '../../common/constants/AppConstants';
import { SliderRow } from '../../components/SliderRow';

@ComponentV2
export struct AdjustSheet {
  @Param vm: EditorViewModel = new EditorViewModel();

  private get isEmoji(): boolean {
    return this.vm.maskKind === MaskKind.EMOJI;
  }

  /** 当前大小比例(0.5~2.5)。 */
  private get sizeFactor(): number {
    if (this.isEmoji && this.vm.editingEmoji) {
      return this.vm.editingEmoji.sizeFactor;
    }
    if (this.vm.editingBlur) {
      return this.vm.editingBlur.sizeFactor;
    }
    return 1;
  }

  /** 当前角度。 */
  private get angle(): number {
    if (this.isEmoji && this.vm.editingEmoji) {
      return this.vm.editingEmoji.angle;
    }
    if (this.vm.editingBlur) {
      return this.vm.editingBlur.angle;
    }
    return 0;
  }

  build() {
    Column() {
      // 头部：标题 + 删除
      Row() {
        Text(this.isEmoji ? $r('app.string.adjust_emoji_title') : $r('app.string.adjust_blur_title'))
          .fontSize($r('app.float.font_headline'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(20).fontColor([$r('app.color.danger')])
        }
        .width(40).height(40).backgroundColor($r('app.color.surface_2'))
        .onClick(() => this.vm.requestDeleteEditing())
      }
      .width('100%').alignItems(VerticalAlign.Center)

      // Emoji 选择(仅表情模式)
      if (this.isEmoji) {
        Row() {
          // 预览
          Text(this.vm.editingEmoji ? this.vm.editingEmoji.emoji : '🙂')
            .fontSize(36)
            .width(64).height(64)
            .textAlign(TextAlign.Center)
            .borderRadius(20)
            .backgroundColor($r('app.color.brand_soft'))
            .borderWidth(2)
            .borderColor($r('app.color.brand'))
          // 调色板
          List({ space: 8 }) {
            ForEach(this.vm.emojiPalette, (e: string) => {
              ListItem() {
                Text(e)
                  .fontSize(28)
                  .width(44).height(44)
                  .textAlign(TextAlign.Center)
                  .onClick(() => this.vm.updateEditingEmojiChar(e))
              }
            }, (e: string, i: number) => `${i}_${e}`)
          }
          .listDirection(Axis.Horizontal)
          .layoutWeight(1)
          .height(64)
          .padding({ left: 12, right: 12 })
          .borderRadius(18)
          .backgroundColor($r('app.color.surface_2'))
          .margin({ left: 12 })
        }
        .width('100%').margin({ top: 16 }).alignItems(VerticalAlign.Center)
      }

      // 大小
      SliderRow({
        icon: null,
        label: $r('app.string.label_size'),
        value: this.sizeFactor,
        valueText: `${Math.round(this.sizeFactor * 100)}%`,
        min: AppConstants.SIZE_FACTOR_MIN,
        max: AppConstants.SIZE_FACTOR_MAX,
        step: 0.01,
        onChange: (v: number, mode: SliderChangeMode): void => {
          this.vm.updateEditingSizeFactor(v);
          this.vm.setSliding(mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving);
        }
      })
        .margin({ top: 16 })

      // 角度
      SliderRow({
        icon: null,
        label: $r('app.string.label_angle'),
        value: this.angle,
        valueText: `${Math.round(this.angle)}°`,
        min: AppConstants.ANGLE_MIN,
        max: AppConstants.ANGLE_MAX,
        step: 1,
        onChange: (v: number, mode: SliderChangeMode): void => {
          this.vm.updateEditingAngle(v);
          this.vm.setSliding(mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving);
        }
      })
        .margin({ top: 12 })

      // 取消 / 完成
      Row() {
        Button({ type: ButtonType.Capsule }) {
          Text($r('app.string.action_cancel')).fontSize($r('app.float.font_body')).fontColor($r('app.color.text_primary'))
        }
        .layoutWeight(1).height(48).backgroundColor($r('app.color.surface_2'))
        .onClick(() => this.vm.cancelEditing())

        Button({ type: ButtonType.Capsule }) {
          Text($r('app.string.action_done')).fontSize($r('app.float.font_body')).fontColor($r('app.color.on_brand'))
        }
        .layoutWeight(1).height(48).backgroundColor($r('app.color.brand')).margin({ left: 12 })
        .onClick(() => this.vm.confirmEditing())
      }
      .width('100%').margin({ top: 18 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 28 })
    .backgroundColor($r('app.color.surface'))
  }
}
