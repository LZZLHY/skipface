/**
 * SkipfaceAbility.ets
 * 分层：入口 / UIAbility
 *
 * 职责：应用入口能力。
 *  - onCreate / onNewWant：处理"分享图片"进入(ACTION_VIEW/SEND，携带图片 uri)，
 *    把 uri 暂存到 AppStorage，供入口页自动进入编辑器。
 *  - onWindowStageCreate：先 await 初始化依赖容器(AppContainer)并应用主题，
 *    再加载入口页内容(保证首屏构建前依赖已就绪，避免分享冷启动竞态)。
 *  - onConfigurationUpdate：系统色彩模式变化时重应用主题并同步系统栏前景色。
 */
import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { window, display } from '@kit.ArkUI';
import { AppContainer } from '../common/di/AppContainer';
import { ThemeManager, ThemeMode } from '../common/theme/ThemeManager';
import { SafeAreaModel } from '../common/safearea/SafeAreaModel';
import { PENDING_SHARE_URI } from '../pages/SkipFaceEntry';
import { Logger } from '../common/utils/Logger';

const TAG: string = 'SkipfaceAbility';

export default class SkipfaceAbility extends UIAbility {
  /** 当前主窗口引用，用于同步系统栏前景色。 */
  private mainWindow: window.Window | null = null;

  onCreate(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.captureShareUri(want);
  }

  /** 应用已在前台时再次被分享拉起。 */
  onNewWant(want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    this.captureShareUri(want);
  }

  /** 从 want 中提取图片 uri 并暂存到 AppStorage。 */
  private captureShareUri(want: Want): void {
    let uri: string = '';
    if (want.uri && want.uri.length > 0) {
      uri = want.uri;
    } else if (want.parameters) {
      // 兼容不同分享来源：直接 uri 参数，或系统分享的 stream 键。
      const params: Record<string, Object> = want.parameters as Record<string, Object>;
      const direct: Object | undefined = params['uri'];
      const stream: Object | undefined = params['ability.params.stream'];
      if (typeof direct === 'string') {
        uri = direct as string;
      } else if (typeof stream === 'string') {
        uri = stream as string;
      }
    }
    if (uri.length > 0) {
      AppStorage.setOrCreate<string>(PENDING_SHARE_URI, uri);
      Logger.info(TAG, 'captured shared image uri');
    }
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // 1) 先 await 初始化容器并应用主题，保证页面构建前依赖已就绪。
    try {
      await AppContainer.instance().init(this.context);
      const mode: ThemeMode = AppContainer.instance().settingsRepo.getThemeMode();
      ThemeManager.apply(this.context.getApplicationContext(), mode);
    } catch (e) {
      Logger.error(TAG, 'AppContainer init failed', e as Error);
    }

    // 2) 加载入口页内容。
    windowStage.loadContent('pages/SkipFaceEntry', (err): void => {
      if (err.code) {
        Logger.error(TAG, 'load content failed');
        return;
      }
      Logger.info(TAG, 'content loaded');
    });

    // 3) 缓存主窗口，开启全屏沉浸式布局并计算安全区内边距，再同步系统栏前景色。
    try {
      this.mainWindow = windowStage.getMainWindowSync();
      await this.mainWindow.setWindowLayoutFullScreen(true);
      this.updateSafeArea();
      // 安全区变化(旋转/折叠/手势条显隐)时刷新。
      this.mainWindow.on('avoidAreaChange', (): void => { this.updateSafeArea(); });
      this.syncSystemBar(this.context.config.colorMode);
    } catch (e) {
      Logger.warn(TAG, 'init window/system bar failed');
    }
  }

  /** 读取系统安全区避让高度(px→vp)并写入可观察模型，供各页面铺底/避让。 */
  private updateSafeArea(): void {
    const win: window.Window | null = this.mainWindow;
    if (!win) {
      return;
    }
    try {
      const density: number = display.getDefaultDisplaySync().densityPixels || 1;
      const sys: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicator: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const model: SafeAreaModel = SafeAreaModel.instance();
      model.top = sys.topRect.height / density;
      model.bottom = Math.max(sys.bottomRect.height, indicator.bottomRect.height) / density;
    } catch (e) {
      Logger.warn(TAG, 'update safe area failed');
    }
  }

  /** 系统配置变化(如深浅模式切换)：跟随系统时即时刷新系统栏前景色。 */
  onConfigurationUpdate(newConfig: Configuration): void {
    this.syncSystemBar(newConfig.colorMode);
  }

  /**
   * 同步系统栏(状态栏)前景色：深色背景用浅色图标，浅色背景用深色图标，避免看不清。
   * @param colorMode 当前系统/应用色彩模式；可能为 undefined(系统未下发)，按浅色处理。
   */
  private syncSystemBar(colorMode: ConfigurationConstant.ColorMode | undefined): void {
    const win: window.Window | null = this.mainWindow;
    if (!win) {
      return;
    }
    const isDark: boolean = colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    try {
      win.setWindowSystemBarProperties({
        statusBarContentColor: isDark ? '#FFFFFF' : '#000000',
        navigationBarContentColor: isDark ? '#FFFFFF' : '#000000'
      });
    } catch (e) {
      Logger.warn(TAG, 'set system bar properties failed');
    }
  }

  onWindowStageDestroy(): void {
    const container = AppContainer.instance();
    if (container.isInitialized()) {
      container.faceDetector.release();
    }
    this.mainWindow = null;
  }
}
