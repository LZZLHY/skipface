/**
 * SettingsWidgets.ets
 * 分层：components / 通用 UI（状态管理 V2）
 *
 * 职责：设置页使用的分组卡片(SettingsSection)与设置行(SettingRow)。
 *   - SettingsSection：分组标题 + 圆角白卡容器(承载若干行)。
 *   - SettingRow     ：标题(+副标题) + 尾部内容(值/箭头 或 自定义控件)。
 */

@ComponentV2
export struct SettingsSection {
  @Param title: ResourceStr = '';
  /** 卡片内容(若干 SettingRow 或自定义)。 */
  @BuilderParam content: () => void;

  build() {
    Column() {
      Text(this.title)
        .fontSize($r('app.float.font_caption'))
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .margin({ left: 4, bottom: 8 })
        .alignSelf(ItemAlign.Start)

      Column() {
        this.content()
      }
      .width('100%')
      .borderRadius($r('app.float.radius_m'))
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
    .margin({ bottom: 18 })
  }
}

@ComponentV2
export struct SettingRow {
  @Param title: ResourceStr = '';
  @Param subtitle: ResourceStr = '';
  @Param valueText: ResourceStr = '';
  @Param showChevron: boolean = false;
  @Param showDivider: boolean = false;
  /** 自定义尾部控件(如 Toggle / SegmentedControl)；提供时忽略 valueText/chevron。 */
  @BuilderParam trailing?: () => void;
  @Event onClickRow: () => void = () => {};

  build() {
    Column() {
      if (this.showDivider) {
        Divider().color($r('app.color.divider')).strokeWidth(1)
      }
      Row() {
        Column() {
          Text(this.title)
            .fontSize($r('app.float.font_body'))
            .fontColor($r('app.color.text_primary'))
          if (this.subtitle) {
            Text(this.subtitle)
              .fontSize($r('app.float.font_label'))
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.trailing) {
          this.trailing()
        } else {
          Row() {
            if (this.valueText) {
              Text(this.valueText)
                .fontSize($r('app.float.font_caption'))
                .fontColor($r('app.color.text_secondary'))
            }
            if (this.showChevron) {
              Image($r('sys.media.ohos_ic_public_arrow_right'))
                .width(18)
                .height(18)
                .fillColor($r('app.color.text_tertiary'))
                .margin({ left: 4 })
            }
          }
          .alignItems(VerticalAlign.Center)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 14 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => this.onClickRow())
    }
    .width('100%')
  }
}
