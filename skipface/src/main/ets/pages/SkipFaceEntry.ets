/**
 * SkipFaceEntry.ets
 * 分层：UI / 路由宿主（应用入口页）
 *
 * 职责：承载 Navigation 路由栈，根内容为首页；按路由名分发到编辑器/设置。
 *       注册响应式断点监听；若由"分享图片"启动(AppStorage 中存在 pendingShareUri)，
 *       自动进入编辑器。
 */
import { HomePage } from './HomePage';
import { EditorPage } from './EditorPage';
import { SettingsPage } from './SettingsPage';
import { BreakpointSystem } from '../common/breakpoint/BreakpointSystem';

/** AppStorage 键：分享进入携带的图片 uri。 */
export const PENDING_SHARE_URI: string = 'pendingShareUri';

@Entry
@ComponentV2
struct SkipFaceEntry {
  @Local pathStack: NavPathStack = new NavPathStack();
  private breakpoint: BreakpointSystem = new BreakpointSystem();

  aboutToAppear(): void {
    this.breakpoint.register(this.getUIContext());
    // 分享启动：若存在待处理 uri，直接进入编辑器。
    const pending: string | undefined = AppStorage.get<string>(PENDING_SHARE_URI);
    if (pending && pending.length > 0) {
      AppStorage.setOrCreate<string>(PENDING_SHARE_URI, '');
      this.pathStack.pushPath({ name: 'editor', param: pending });
    }
  }

  aboutToDisappear(): void {
    this.breakpoint.unregister();
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

  build() {
    Navigation(this.pathStack) {
      HomePage({ pathStack: this.pathStack })
    }
    .navDestination(this.routerMap)
    .mode(NavigationMode.Auto)
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
  }
}
