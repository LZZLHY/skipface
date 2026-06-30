/**
 * SegmentedControl.ets
 * 分层：components / 通用 UI（状态管理 V2）
 *
 * 职责：胶囊分段控制器。每段含图标(可选)+文案，选中段高亮(品牌色+表面底+轻投影)。
 *       通过 @Param 接收选项与当前索引，通过 @Event 上抛选择事件。
 */

/** 单个分段项。 */
export interface SegItem {
  label: ResourceStr;
  /** 可选图标(Material/系统符号名或本地资源)。这里用系统 SymbolGlyph 资源或 Image。 */
  icon?: Resource;
}

@ComponentV2
export struct SegmentedControl {
  /** 选项列表。 */
  @Param options: SegItem[] = [];
  /** 当前选中索引。 */
  @Param selected: number = 0;
  /** 是否撑满宽度(平铺等分)。 */
  @Param fill: boolean = false;
  /** 选择回调。 */
  @Event onSelect: (index: number) => void = () => {};

  build() {
    Row() {
      ForEach(this.options, (item: SegItem, index: number) => {
        Row() {
          if (item.icon) {
            Image(item.icon)
              .width(18)
              .height(18)
              .fillColor(index === this.selected ? $r('app.color.brand') : $r('app.color.text_secondary'))
              .margin({ right: 6 })
          }
          Text(item.label)
            .fontSize($r('app.float.font_caption'))
            .fontWeight(index === this.selected ? FontWeight.Bold : FontWeight.Medium)
            .fontColor(index === this.selected ? $r('app.color.brand') : $r('app.color.text_secondary'))
        }
        .layoutWeight(this.fill ? 1 : 0)
        .justifyContent(FlexAlign.Center)
        .padding({ top: 8, bottom: 8, left: 18, right: 18 })
        .borderRadius(10)
        .backgroundColor(index === this.selected ? $r('app.color.surface') : Color.Transparent)
        .shadow(index === this.selected
          ? { radius: 4, color: '#1A000000', offsetX: 0, offsetY: 1 }
          : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
        .onClick(() => this.onSelect(index))
      }, (item: SegItem, index: number) => `${index}_${item.label}`)
    }
    .padding(3)
    .borderRadius(13)
    .backgroundColor($r('app.color.surface_2'))
  }
}
