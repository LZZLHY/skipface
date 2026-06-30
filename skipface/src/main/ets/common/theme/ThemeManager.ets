/**
 * ThemeManager.ets
 * 分层：common / 主题
 *
 * 职责：管理"明暗主题三态"（跟随系统/浅色/深色）：
 *  - 把用户选择映射为系统色彩模式并应用到 ApplicationContext；
 *  - 颜色取值本身由资源系统(base/dark element/color.json)自动切换，
 *    本类只负责切换"色彩模式"，不直接操作具体颜色。
 *
 * 说明：具体颜色一律通过 $r('app.color.*') 引用，深浅自动适配，禁止硬编码。
 */
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { Logger } from '../utils/Logger';

/** 主题模式三态。数值与 Preferences 中持久化的整数一致。 */
export enum ThemeMode {
  /** 跟随系统。 */
  SYSTEM = 0,
  /** 强制浅色。 */
  LIGHT = 1,
  /** 强制深色。 */
  DARK = 2
}

export class ThemeManager {
  private static readonly TAG: string = 'ThemeManager';

  /**
   * 将主题模式应用到应用级上下文。
   * @param context 应用级上下文（getApplicationContext()）。
   * @param mode    目标主题模式。
   */
  static apply(context: common.ApplicationContext, mode: ThemeMode): void {
    const colorMode: ConfigurationConstant.ColorMode = ThemeManager.toColorMode(mode);
    try {
      context.setColorMode(colorMode);
      Logger.info(ThemeManager.TAG, `applied theme mode = ${mode}`);
    } catch (e) {
      Logger.error(ThemeManager.TAG, 'apply theme mode failed', e as Error);
    }
  }

  /** 主题模式 → 系统色彩模式枚举。 */
  private static toColorMode(mode: ThemeMode): ConfigurationConstant.ColorMode {
    switch (mode) {
      case ThemeMode.LIGHT:
        return ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
      case ThemeMode.DARK:
        return ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
      case ThemeMode.SYSTEM:
      default:
        return ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET; // 跟随系统
    }
  }
}
