/**
 * SettingsRepository.ets
 * 分层：data / 数据层
 *
 * 职责：基于 @kit.ArkData 的 Preferences 持久化所有用户设置，并提供
 *       带内存缓存的读写接口。读操作异常回退默认值，写操作异常记录日志后吞掉。
 *
 * 持久化项：
 *  - emojiPalette  预置 emoji 列表（JSON 数组字符串）
 *  - fonts         自定义字体路径列表 / selectedFont 选中字体路径
 *  - defaultMaskKind / defaultBlurEffect / defaultBlurTarget  默认遮挡偏好
 *  - themeMode     主题模式（0 系统 / 1 浅 / 2 深）
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { AppConstants, PrefKeys } from '../../common/constants/AppConstants';
import { MaskKind, BlurEffect, BlurTarget } from '../../domain/model/MaskEnums';
import { ThemeMode } from '../../common/theme/ThemeManager';
import { EmojiUtil } from '../../common/utils/EmojiUtil';
import { Logger } from '../../common/utils/Logger';

/** 默认 emoji 调色板。 */
const DEFAULT_EMOJI_PALETTE: string[] = ['😂', '😎', '😆', '😋', '😊', '😜', '🤠'];
/** 默认字体标记（表示使用系统默认字体渲染 emoji）。 */
export const DEFAULT_FONT_MARKER: string = 'DEFAULT';

export class SettingsRepository {
  private static readonly TAG: string = 'SettingsRepository';
  private store: preferences.Preferences | null = null;

  /**
   * 初始化 Preferences。必须在使用其它方法前调用一次。
   * @param context UIAbility 或应用级上下文。
   */
  async init(context: common.Context): Promise<void> {
    if (this.store) {
      return;
    }
    try {
      const options: preferences.Options = { name: AppConstants.PREF_STORE_NAME };
      this.store = preferences.getPreferencesSync(context, options);
      Logger.info(SettingsRepository.TAG, 'preferences initialized');
    } catch (e) {
      Logger.error(SettingsRepository.TAG, 'init preferences failed', e as Error);
    }
  }

  /** 读取字符串，异常或缺失时回退默认。 */
  private getStr(key: string, def: string): string {
    if (!this.store) {
      return def;
    }
    try {
      return this.store.getSync(key, def) as string;
    } catch (e) {
      Logger.warn(SettingsRepository.TAG, `getStr ${key} failed`);
      return def;
    }
  }

  private getInt(key: string, def: number): number {
    if (!this.store) {
      return def;
    }
    try {
      return this.store.getSync(key, def) as number;
    } catch (e) {
      Logger.warn(SettingsRepository.TAG, `getInt ${key} failed`);
      return def;
    }
  }

  /** 写入并落盘，异常吞掉并记录。 */
  private async put(key: string, value: preferences.ValueType): Promise<void> {
    if (!this.store) {
      return;
    }
    try {
      this.store.putSync(key, value);
      await this.store.flush();
    } catch (e) {
      Logger.error(SettingsRepository.TAG, `put ${key} failed`, e as Error);
    }
  }

  /** ====== Emoji 调色板 ====== */

  getEmojiPalette(): string[] {
    const raw: string = this.getStr(PrefKeys.EMOJI_PALETTE, '');
    if (!raw) {
      return DEFAULT_EMOJI_PALETTE.slice();
    }
    try {
      const parsed: Object = JSON.parse(raw) as Object;
      const list: string[] = SettingsRepository.decodePalette(parsed);
      return list.length > 0 ? list : DEFAULT_EMOJI_PALETTE.slice();
    } catch (e) {
      Logger.warn(SettingsRepository.TAG, 'parse emoji palette failed, fallback to default');
      return DEFAULT_EMOJI_PALETTE.slice();
    }
  }

  /**
   * 解析存储内容为 emoji 列表，兼容两种格式：
   *  - 新格式 number[][]：每个 emoji 用其 Unicode 码位数组表示(纯数字，绝不会被存储层损坏)。
   *  - 旧格式 string[]   ：拼接后按字素重新切分以修复被拆散的代理对，并过滤无效项。
   */
  private static decodePalette(parsed: Object): string[] {
    if (!Array.isArray(parsed) || parsed.length === 0) {
      return [];
    }
    const arr: Object[] = parsed as Object[];
    // 新格式：number[][]（每项是该 emoji 的 UTF-16 码元序列）
    if (Array.isArray(arr[0])) {
      const result: string[] = [];
      for (const item of arr) {
        const units: number[] = item as number[];
        let s: string = '';
        for (const u of units) {
          if (typeof u === 'number' && u > 0) {
            s += String.fromCharCode(u);
          }
        }
        if (SettingsRepository.isStandaloneEmoji(s)) {
          result.push(s);
        }
      }
      return result;
    }
    // 旧字符串格式：修复后切分。
    const strs: string[] = arr as string[];
    const joined: string = strs.join('').replace(/[\u003f\ufffd]/g, '');
    return EmojiUtil.split(joined).filter((e: string): boolean => SettingsRepository.isStandaloneEmoji(e));
  }

  /** 判断字符串是否为一个完整独立的可显示符号：无孤立代理项、无 '?'/替换符、且含非 ASCII 码位。 */
  private static isStandaloneEmoji(e: string): boolean {
    if (!e || e.length === 0) {
      return false;
    }
    let hasNonAscii: boolean = false;
    for (let i: number = 0; i < e.length; i++) {
      const c: number = e.charCodeAt(i);
      if (c === 0x3f || c === 0xfffd) {
        return false; // '?' 或 替换字符 �
      }
      if (c >= 0xd800 && c <= 0xdbff) {
        const next: number = i + 1 < e.length ? e.charCodeAt(i + 1) : -1;
        if (next < 0xdc00 || next > 0xdfff) {
          return false; // 孤立高位代理
        }
        i++;
        hasNonAscii = true;
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        return false; // 孤立低位代理
      } else if (c >= 0x80) {
        hasNonAscii = true;
      }
    }
    return hasNonAscii;
  }

  async setEmojiPalette(palette: string[]): Promise<void> {
    const value: string[] = palette.length > 0 ? palette : DEFAULT_EMOJI_PALETTE.slice();
    // 以"UTF-16 码元整数数组"持久化(纯数字)：彻底规避存储层对 4 字节 emoji 的编码损坏，
    // 且用 charCodeAt 逐码元处理，不依赖 Array.from/for-of 的码点迭代行为。
    const cps: number[][] = value.map((e: string): number[] => {
      const arr: number[] = [];
      for (let i: number = 0; i < e.length; i++) {
        arr.push(e.charCodeAt(i));
      }
      return arr;
    });
    await this.put(PrefKeys.EMOJI_PALETTE, JSON.stringify(cps));
  }

  /** ====== 字体 ====== */

  /** 字体列表始终以"默认字体标记"打头。 */
  getFonts(): string[] {
    const raw: string = this.getStr(PrefKeys.FONT_LIST, '');
    const stored: string[] = raw ? raw.split(',').filter((s: string): boolean => s.length > 0) : [];
    return [DEFAULT_FONT_MARKER].concat(stored);
  }

  getSelectedFont(): string {
    const selected: string = this.getStr(PrefKeys.SELECTED_FONT, DEFAULT_FONT_MARKER);
    return this.getFonts().includes(selected) ? selected : DEFAULT_FONT_MARKER;
  }

  async addFont(fontPath: string): Promise<void> {
    const raw: string = this.getStr(PrefKeys.FONT_LIST, '');
    const list: string[] = raw ? raw.split(',').filter((s: string): boolean => s.length > 0) : [];
    if (!list.includes(fontPath)) {
      list.push(fontPath);
    }
    await this.put(PrefKeys.FONT_LIST, list.join(','));
  }

  async removeFont(fontPath: string): Promise<void> {
    const raw: string = this.getStr(PrefKeys.FONT_LIST, '');
    const list: string[] = raw ? raw.split(',').filter((s: string): boolean => s.length > 0 && s !== fontPath) : [];
    await this.put(PrefKeys.FONT_LIST, list.join(','));
    if (this.getSelectedFont() === fontPath) {
      await this.put(PrefKeys.SELECTED_FONT, DEFAULT_FONT_MARKER);
    }
  }

  async setSelectedFont(fontPath: string): Promise<void> {
    await this.put(PrefKeys.SELECTED_FONT, fontPath);
  }

  /** ====== 默认遮挡偏好 ====== */

  getDefaultMaskKind(): MaskKind {
    return this.getInt(PrefKeys.DEFAULT_MASK_KIND, MaskKind.EMOJI) as MaskKind;
  }

  async setDefaultMaskKind(kind: MaskKind): Promise<void> {
    await this.put(PrefKeys.DEFAULT_MASK_KIND, kind as number);
  }

  getDefaultBlurEffect(): BlurEffect {
    return this.getInt(PrefKeys.DEFAULT_BLUR_EFFECT, BlurEffect.GAUSSIAN) as BlurEffect;
  }

  async setDefaultBlurEffect(effect: BlurEffect): Promise<void> {
    await this.put(PrefKeys.DEFAULT_BLUR_EFFECT, effect as number);
  }

  getDefaultBlurTarget(): BlurTarget {
    return this.getInt(PrefKeys.DEFAULT_BLUR_TARGET, BlurTarget.FACE) as BlurTarget;
  }

  async setDefaultBlurTarget(target: BlurTarget): Promise<void> {
    await this.put(PrefKeys.DEFAULT_BLUR_TARGET, target as number);
  }

  /** ====== 主题模式 ====== */

  getThemeMode(): ThemeMode {
    return this.getInt(PrefKeys.THEME_MODE, ThemeMode.SYSTEM) as ThemeMode;
  }

  async setThemeMode(mode: ThemeMode): Promise<void> {
    await this.put(PrefKeys.THEME_MODE, mode as number);
  }

  /** ====== 隐私政策同意（首次启动门控） ====== */

  /** 是否已同意隐私政策（默认 false，未同意则首启弹窗）。 */
  getPrivacyAgreed(): boolean {
    if (!this.store) {
      return false;
    }
    try {
      return this.store.getSync(PrefKeys.PRIVACY_AGREED, false) as boolean;
    } catch (e) {
      Logger.warn(SettingsRepository.TAG, 'getPrivacyAgreed failed');
      return false;
    }
  }

  async setPrivacyAgreed(agreed: boolean): Promise<void> {
    await this.put(PrefKeys.PRIVACY_AGREED, agreed);
  }
}
