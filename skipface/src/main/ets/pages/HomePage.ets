/**
 * HomePage.ets
 * 分层：UI / 页面（首页/着陆）
 *
 * 职责：品牌与隐私主张展示 + 主/次入口(选择照片/拍摄)。点击后选图并跳转编辑器。
 *       右上角进入设置。布局自适应：内容居中，主操作在下半部便于单手触达。
 */
import { common } from '@kit.AbilityKit';
import { AppContainer } from '../common/di/AppContainer';
import { SafeAreaModel } from '../common/safearea/SafeAreaModel';
import { Logger } from '../common/utils/Logger';

@ComponentV2
export struct HomePage {
  /** 路由栈(由 Entry 注入)。 */
  @Param pathStack: NavPathStack = new NavPathStack();
  /** 系统安全区内边距(沉浸式布局下用于避让状态栏/手势条)。 */
  @Local safe: SafeAreaModel = SafeAreaModel.instance();

  private async onPickPhoto(): Promise<void> {
    try {
      const uri: string = await AppContainer.instance().photoRepo.pickImage();
      if (uri) {
        this.pathStack.pushPath({ name: 'editor', param: uri });
      }
    } catch (e) {
      Logger.error('HomePage', 'pick photo failed', e as Error);
    }
  }

  private async onTakePhoto(): Promise<void> {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const uri: string = await AppContainer.instance().photoRepo.capturePhoto(ctx);
      if (uri) {
        this.pathStack.pushPath({ name: 'editor', param: uri });
      }
    } catch (e) {
      Logger.error('HomePage', 'take photo failed', e as Error);
    }
  }

  private onOpenSettings(): void {
    this.pathStack.pushPath({ name: 'settings' });
  }

  build() {
    Column() {
      // 顶部：右上角设置入口
      Row() {
        Blank()
        Button({ type: ButtonType.Circle, stateEffect: true }) {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(22)
            .fontColor([$r('app.color.text_secondary')])
        }
        .width(40)
        .height(40)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.onOpenSettings())
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: this.safe.top + 8 })

      // 中部：品牌 Hero
      Column() {
        Column() {
          SymbolGlyph($r('sys.symbol.face_smiling'))
            .fontSize(46)
            .fontColor([$r('app.color.on_brand')])
        }
        .width(84)
        .height(84)
        .borderRadius(24)
        .backgroundColor($r('app.color.brand'))
        .justifyContent(FlexAlign.Center)
        .shadow({ radius: 24, color: '#405B6CFF', offsetX: 0, offsetY: 8 })

        Text($r('app.string.app_name'))
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 20 })

        Text($r('app.string.home_tagline'))
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .lineHeight(22)
          .margin({ top: 12 })

        // 隐私徽标
        Row() {
          SymbolGlyph($r('sys.symbol.lock'))
            .fontSize(16)
            .fontColor([$r('app.color.brand_deep')])
            .margin({ right: 6 })
          Text($r('app.string.home_privacy'))
            .fontSize($r('app.float.font_label'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand_deep'))
        }
        .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        .borderRadius(16)
        .backgroundColor($r('app.color.brand_soft'))
        .margin({ top: 20 })
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 32, right: 32 })

      // 底部：主/次操作
      Column() {
        Button() {
          Row() {
            SymbolGlyph($r('sys.symbol.picture'))
              .fontSize(22)
              .fontColor([$r('app.color.on_brand')])
              .margin({ right: 8 })
            Text($r('app.string.action_pick_photo'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.on_brand'))
          }
        }
        .width('100%')
        .height(52)
        .borderRadius(26)
        .backgroundColor($r('app.color.brand'))
        .onClick(() => this.onPickPhoto())

        Button() {
          Row() {
            SymbolGlyph($r('sys.symbol.camera'))
              .fontSize(22)
              .fontColor([$r('app.color.text_primary')])
              .margin({ right: 8 })
            Text($r('app.string.action_take_photo'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
          }
        }
        .width('100%')
        .height(52)
        .borderRadius(26)
        .backgroundColor($r('app.color.surface'))
        .borderWidth(1.5)
        .borderColor($r('app.color.divider'))
        .margin({ top: 12 })
        .onClick(() => this.onTakePhoto())
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: this.safe.bottom + 32 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
