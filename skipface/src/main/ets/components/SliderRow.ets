/**
 * SliderRow.ets
 * 分层：components / 通用 UI（状态管理 V2）
 *
 * 职责：带"图标 + 标题 + 实时数值 + 滑块"的一行控件。用于调整大小/角度。
 */
@ComponentV2
export struct SliderRow {
  @Param icon: Resource | null = null;
  @Param label: ResourceStr = '';
  /** 当前值。 */
  @Param value: number = 0;
  /** 数值显示文案(如 "120%"、"-8°")。 */
  @Param valueText: string = '';
  @Param min: number = 0;
  @Param max: number = 1;
  @Param step: number = 0.01;
  /** 拖动回调：value 为当前值，mode 为拖动阶段(开始/拖动中/结束/点击)。 */
  @Event onChange: (value: number, mode: SliderChangeMode) => void = () => {};

  build() {
    Column() {
      Row() {
        Row() {
          if (this.icon) {
            Image(this.icon)
              .width(18)
              .height(18)
              .fillColor($r('app.color.text_secondary'))
              .margin({ right: 6 })
          }
          Text(this.label)
            .fontSize($r('app.float.font_body'))
            .fontColor($r('app.color.text_primary'))
        }

        Text(this.valueText)
          .fontSize($r('app.float.font_caption'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      Slider({
        value: this.value,
        min: this.min,
        max: this.max,
        step: this.step,
        style: SliderStyle.OutSet
      })
        .width('100%')
        .blockColor($r('app.color.surface'))
        .selectedColor($r('app.color.brand'))
        .trackColor($r('app.color.surface_2'))
        .onChange((v: number, mode: SliderChangeMode) => this.onChange(v, mode))
    }
    .width('100%')
  }
}
