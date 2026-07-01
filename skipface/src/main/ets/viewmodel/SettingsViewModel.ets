/**
 * SettingsViewModel.ets
 * 分层：状态层（@ObservedV2）
 *
 * 职责：设置页的状态与动作。读写 SettingsRepository 并应用主题模式；
 *       管理 emoji 调色板、字体、隐藏图标、默认遮挡偏好。
 */
import { common, bundleManager } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AppContainer } from '../common/di/AppContainer';
import { ThemeMode, ThemeManager } from '../common/theme/ThemeManager';
import { MaskKind, BlurEffect, BlurTarget } from '../domain/model/MaskEnums';
import { EmojiUtil } from '../common/utils/EmojiUtil';
import { DEFAULT_FONT_MARKER } from '../data/settings/SettingsRepository';
import { Logger } from '../common/utils/Logger';

@ObservedV2
export class SettingsViewModel {
  private static readonly TAG: string = 'SettingsViewModel';

  @Trace themeMode: ThemeMode = ThemeMode.SYSTEM;
  @Trace emojiPalette: string[] = [];
  @Trace fonts: string[] = [DEFAULT_FONT_MARKER];
  @Trace selectedFont: string = DEFAULT_FONT_MARKER;
  @Trace defaultMaskKind: MaskKind = MaskKind.EMOJI;
  @Trace defaultBlurEffect: BlurEffect = BlurEffect.GAUSSIAN;
  @Trace defaultBlurTarget: BlurTarget = BlurTarget.FACE;
  @Trace appVersion: string = '1.0.0';

  private context: common.UIAbilityContext | null = null;

  private get repo() {
    return AppContainer.instance().settingsRepo;
  }

  /** 绑定上下文并载入全部设置。 */
  async attach(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    this.themeMode = this.repo.getThemeMode();
    this.emojiPalette = this.repo.getEmojiPalette();
    this.fonts = this.repo.getFonts();
    this.selectedFont = this.repo.getSelectedFont();
    this.defaultMaskKind = this.repo.getDefaultMaskKind();
    this.defaultBlurEffect = this.repo.getDefaultBlurEffect();
    this.defaultBlurTarget = this.repo.getDefaultBlurTarget();
    await this.loadVersion();
  }

  private async loadVersion(): Promise<void> {
    try {
      const info: bundleManager.BundleInfo =
        await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
      this.appVersion = info.versionName;
    } catch (e) {
      Logger.warn(SettingsViewModel.TAG, 'read version failed');
    }
  }

  /** ====== 主题 ====== */
  async setThemeMode(mode: ThemeMode): Promise<void> {
    this.themeMode = mode;
    await this.repo.setThemeMode(mode);
    const ctx: common.UIAbilityContext | null = this.context;
    if (ctx) {
      ThemeManager.apply(ctx.getApplicationContext(), mode);
    }
  }

  /** ====== Emoji 调色板 ====== */
  /**
   * 把输入文本中的 emoji 追加到调色板末尾(去重)，立即更新内存列表并持久化。
   * 直接改内存数组以保证 UI 即时刷新，不依赖存储回读。
   */
  async addEmojis(text: string): Promise<void> {
    const additions: string[] = EmojiUtil.split(text);
    if (additions.length === 0) {
      return;
    }
    const next: string[] = this.emojiPalette.slice();
    for (const e of additions) {
      if (e.trim().length > 0 && !next.includes(e)) {
        next.push(e);
      }
    }
    if (next.length === this.emojiPalette.length) {
      return; // 没有新增(全是重复)
    }
    this.emojiPalette = next;          // 即时刷新
    await this.repo.setEmojiPalette(next);
  }

  /** 删除指定下标的 emoji。全删则恢复默认。 */
  async removeEmojiAt(index: number): Promise<void> {
    if (index < 0 || index >= this.emojiPalette.length) {
      return;
    }
    const next: string[] = this.emojiPalette.slice();
    next.splice(index, 1);
    this.emojiPalette = next.length > 0 ? next : this.repo.getEmojiPalette();
    await this.repo.setEmojiPalette(next);
    if (next.length === 0) {
      this.emojiPalette = this.repo.getEmojiPalette();
    }
  }

  /** ====== 字体 ====== */
  /** 复制所选字体文件到应用沙箱并加入列表。 */
  async addFont(srcUri: string, displayName: string): Promise<void> {
    const ctx: common.UIAbilityContext | null = this.context;
    if (!ctx) {
      return;
    }
    const ext: string = displayName.toLowerCase().endsWith('.otf') ? '.otf' : '.ttf';
    const dir: string = `${ctx.filesDir}/fonts`;
    const dest: string = `${dir}/font_${Date.now()}${ext}`;
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
      const srcFile: fs.File = fs.openSync(srcUri, fs.OpenMode.READ_ONLY);
      const dstFile: fs.File = fs.openSync(dest, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        fs.copyFileSync(srcFile.fd, dstFile.fd);
      } finally {
        fs.closeSync(srcFile.fd);
        fs.closeSync(dstFile.fd);
      }
    } catch (e) {
      Logger.error(SettingsViewModel.TAG, 'copy font failed', e as Error);
      return;
    }
    await this.repo.addFont(dest);
    this.fonts = this.repo.getFonts();
  }

  async removeFont(path: string): Promise<void> {
    if (path === DEFAULT_FONT_MARKER) {
      return;
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      Logger.warn(SettingsViewModel.TAG, 'delete font file failed');
    }
    await this.repo.removeFont(path);
    this.fonts = this.repo.getFonts();
    this.selectedFont = this.repo.getSelectedFont();
  }

  async selectFont(path: string): Promise<void> {
    this.selectedFont = path;
    await this.repo.setSelectedFont(path);
  }

  /** ====== 默认遮挡偏好 ====== */
  async setDefaultMaskKind(kind: MaskKind): Promise<void> {
    this.defaultMaskKind = kind;
    await this.repo.setDefaultMaskKind(kind);
  }

  async setDefaultBlurEffect(effect: BlurEffect): Promise<void> {
    this.defaultBlurEffect = effect;
    await this.repo.setDefaultBlurEffect(effect);
  }

  async setDefaultBlurTarget(target: BlurTarget): Promise<void> {
    this.defaultBlurTarget = target;
    await this.repo.setDefaultBlurTarget(target);
  }
}
