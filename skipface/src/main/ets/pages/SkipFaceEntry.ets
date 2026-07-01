/**
 * SkipFaceEntry.ets
 * 分层：UI / 路由宿主（应用入口页）
 *
 * 职责：承载 Navigation 路由栈，根内容为首页；按路由名分发到编辑器/设置。
 *       注册响应式断点监听；若由"分享图片"启动(AppStorage 中存在 pendingShareUri)，
 *       自动进入编辑器。
 *
 * 上架合规：首次启动弹出"隐私政策"同意门控——未同意前遮罩全屏、不可使用；
 *       同意后持久化标记并放行（若为分享启动则随后自动进入编辑器）；不同意则退出应用。
 */
import { common } from '@kit.AbilityKit';
import { HomePage } from './HomePage';
import { EditorPage } from './EditorPage';
import { SettingsPage } from './SettingsPage';
import { BreakpointSystem } from '../common/breakpoint/BreakpointSystem';
import { AppContainer } from '../common/di/AppContainer';
import { AppConstants } from '../common/constants/AppConstants';
import { Logger } from '../common/utils/Logger';

/** AppStorage 键：分享进入携带的图片 uri。 */
export const PENDING_SHARE_URI: string = 'pendingShareUri';

@Entry
@ComponentV2
struct SkipFaceEntry {
  @Local pathStack: NavPathStack = new NavPathStack();
  /** 是否显示隐私政策同意门控（首次启动且未同意时为 true）。 */
  @Local privacyGateShown: boolean = false;
  private breakpoint: BreakpointSystem = new BreakpointSystem();
  /** 分享启动携带的待处理 uri：未同意隐私前暂存，同意后再进入编辑器。 */
  private pendingShareUri: string = '';

  aboutToAppear(): void {
    this.breakpoint.register(this.getUIContext());

    // 取出分享启动携带的 uri（若有）并从 AppStorage 清除。
    const pending: string | undefined = AppStorage.get<string>(PENDING_SHARE_URI);
    if (pending && pending.length > 0) {
      this.pendingShareUri = pending;
      AppStorage.setOrCreate<string>(PENDING_SHARE_URI, '');
    }

    // 隐私政策门控：未同意则弹窗，暂不放行；已同意则按需进入编辑器。
    const agreed: boolean = this.readPrivacyAgreed();
    if (!agreed) {
      this.privacyGateShown = true;
    } else {
      this.consumePendingShare();
    }
  }

  aboutToDisappear(): void {
    this.breakpoint.unregister();
  }

  /** 读取隐私同意标记（容器未就绪时按未同意处理，稳妥弹窗）。 */
  private readPrivacyAgreed(): boolean {
    const container: AppContainer = AppContainer.instance();
    if (!container.isInitialized()) {
      return false;
    }
    return container.settingsRepo.getPrivacyAgreed();
  }

  /** 若存在分享待处理 uri，进入编辑器。 */
  private consumePendingShare(): void {
    if (this.pendingShareUri.length > 0) {
      const uri: string = this.pendingShareUri;
      this.pendingShareUri = '';
      this.pathStack.pushPath({ name: 'editor', param: uri });
    }
  }

  /** 同意隐私政策：持久化标记、关闭门控、放行分享跳转。 */
  private onAgreePrivacy(): void {
    const container: AppContainer = AppContainer.instance();
    if (container.isInitialized()) {
      container.settingsRepo.setPrivacyAgreed(true).catch((): void => {
        Logger.warn('SkipFaceEntry', 'persist privacy agreement failed');
      });
    }
    this.privacyGateShown = false;
    this.consumePendingShare();
  }

  /** 不同意：退出应用。 */
  private onDisagreePrivacy(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.terminateSelf();
    } catch (e) {
      Logger.warn('SkipFaceEntry', 'terminate self failed');
    }
  }

  /** 打开完整隐私政策网页。 */
  private onViewPrivacy(): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.openLink(AppConstants.PRIVACY_URL, { appLinkingOnly: false }).catch((): void => {
        Logger.warn('SkipFaceEntry', 'open privacy url failed');
      });
    } catch (e) {
      Logger.warn('SkipFaceEntry', 'open privacy url failed');
    }
  }

  @Builder
  routerMap(name: string, param: Object) {
    NavDestination() {
      if (name === 'editor') {
        EditorPage({ pathStack: this.pathStack, uri: param as string })
      } else if (name === 'settings') {
        SettingsPage({ pathStack: this.pathStack })
      }
    }
    .hideTitleBar(true)
  }

  /** 首次启动隐私政策同意门控：全屏遮罩 + 居中卡片，同意前不可使用。 */
  @Builder
  privacyGate() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))

      Column() {
        Text($r('app.string.privacy_gate_title'))
          .fontSize($r('app.float.font_title'))
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        Scroll() {
          Text($r('app.string.privacy_gate_summary'))
            .fontSize($r('app.float.font_body'))
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(22)
        }
        .constraintSize({ maxHeight: 260 })
        .margin({ top: 14 })

        Text($r('app.string.privacy_gate_view'))
          .fontSize($r('app.float.font_body'))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.brand'))
          .margin({ top: 14 })
          .onClick(() => this.onViewPrivacy())

        Button({ type: ButtonType.Capsule }) {
          Text($r('app.string.privacy_gate_agree'))
            .fontSize($r('app.float.font_body'))
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.on_brand'))
        }
        .width('100%')
        .height(48)
        .backgroundColor($r('app.color.brand'))
        .margin({ top: 20 })
        .onClick(() => this.onAgreePrivacy())

        Button({ type: ButtonType.Capsule }) {
          Text($r('app.string.privacy_gate_disagree'))
            .fontSize($r('app.float.font_caption'))
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height(44)
        .backgroundColor(Color.Transparent)
        .margin({ top: 8 })
        .onClick(() => this.onDisagreePrivacy())
      }
      .width('84%')
      .padding(24)
      .borderRadius($r('app.float.radius_l'))
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      Navigation(this.pathStack) {
        HomePage({ pathStack: this.pathStack })
      }
      .navDestination(this.routerMap)
      .mode(NavigationMode.Auto)
      .hideTitleBar(true)
      .width('100%')
      .height('100%')

      if (this.privacyGateShown) {
        this.privacyGate()
      }
    }
    .width('100%')
    .height('100%')
  }
}
