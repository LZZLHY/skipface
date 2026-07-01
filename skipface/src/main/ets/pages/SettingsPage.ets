/**
 * SettingsPage.ets
 * 分层：UI / 页面（设置，整页分组列表）
 *
 * 职责：外观(明暗三态)、遮挡偏好(默认模式/效果/目标)、表情与字体、隐私、关于。
 *       所有变更即时持久化(SettingsViewModel)。
 *
 * 说明：分组内容与行尾控件均以"具名 @Builder + 按引用传入 @BuilderParam"的方式组织，
 *       符合 ArkTS 对 @BuilderParam 的传参规范。
 */
import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { SettingsViewModel } from '../viewmodel/SettingsViewModel';
import { ThemeMode } from '../common/theme/ThemeManager';
import { MaskKind, BlurEffect, BlurTarget } from '../domain/model/MaskEnums';
import { DEFAULT_FONT_MARKER } from '../data/settings/SettingsRepository';
import { SegmentedControl, SegItem } from '../components/SegmentedControl';
import { SettingsSection, SettingRow } from '../components/SettingsWidgets';
import { SafeAreaModel } from '../common/safearea/SafeAreaModel';
import { AppConstants } from '../common/constants/AppConstants';
import { Logger } from '../common/utils/Logger';

@ComponentV2
export struct SettingsPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  @Local vm: SettingsViewModel = new SettingsViewModel();
  /** 新增 Emoji 输入框文本。 */
  @Local addText: string = '';
  /** 系统安全区内边距(沉浸式布局下用于避让状态栏/手势条)。 */
  @Local safe: SafeAreaModel = SafeAreaModel.instance();

  private themeOptions: SegItem[] = [
    { label: $r('app.string.theme_system') },
    { label: $r('app.string.theme_light') },
    { label: $r('app.string.theme_dark') }
  ];
  private modeOptions: SegItem[] = [
    { label: $r('app.string.mode_emoji') },
    { label: $r('app.string.mode_blur') }
  ];
  private effectOptions: SegItem[] = [
    { label: $r('app.string.effect_gaussian') },
    { label: $r('app.string.effect_pixelate') },
    { label: $r('app.string.effect_halftone') }
  ];
  private targetOptions: SegItem[] = [
    { label: $r('app.string.target_face') },
    { label: $r('app.string.target_eyes') }
  ];

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.vm.attach(ctx);
  }

  private async onAddFont(): Promise<void> {
    try {
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker();
      const opts: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      opts.maxSelectNumber = 1;
      opts.fileSuffixFilters = ['.ttf', '.otf'];
      const uris: string[] = await docPicker.select(opts);
      if (uris.length > 0) {
        const uri: string = uris[0];
        const name: string = uri.substring(uri.lastIndexOf('/') + 1);
        await this.vm.addFont(uri, name);
      }
    } catch (e) {
      Logger.error('SettingsPage', 'add font failed', e as Error);
    }
  }

  private fontFileName(path: string): string {
    const base: string = path.substring(path.lastIndexOf('/') + 1);
    const dot: number = base.lastIndexOf('.');
    return dot > 0 ? base.substring(0, dot) : base;
  }

  /** ====== 行尾控件 Builders ====== */
  @Builder
  themeTrailing() {
    SegmentedControl({
      options: this.themeOptions,
      selected: this.vm.themeMode as number,
      onSelect: (i: number): void => { this.vm.setThemeMode(i as ThemeMode); }
    })
  }

  @Builder
  modeTrailing() {
    SegmentedControl({
      options: this.modeOptions,
      selected: this.vm.defaultMaskKind as number,
      onSelect: (i: number): void => { this.vm.setDefaultMaskKind(i as MaskKind); }
    })
  }

  @Builder
  effectTrailing() {
    SegmentedControl({
      options: this.effectOptions,
      selected: this.vm.defaultBlurEffect as number,
      onSelect: (i: number): void => { this.vm.setDefaultBlurEffect(i as BlurEffect); }
    })
  }

  @Builder
  targetTrailing() {
    SegmentedControl({
      options: this.targetOptions,
      selected: this.vm.defaultBlurTarget as number,
      onSelect: (i: number): void => { this.vm.setDefaultBlurTarget(i as BlurTarget); }
    })
  }

  @Builder
  fontTrailing() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Text($r('app.string.action_add')).fontSize($r('app.float.font_caption')).fontColor($r('app.color.brand'))
    }
    .height(36).backgroundColor($r('app.color.brand_soft')).padding({ left: 14, right: 14 })
    .onClick(() => this.onAddFont())
  }

  /** ====== 分组内容 Builders ====== */
  @Builder
  appearanceContent() {
    SettingRow({ title: $r('app.string.theme_mode_label'), trailing: (): void => { this.themeTrailing() } })
  }

  @Builder
  maskPrefContent() {
    SettingRow({ title: $r('app.string.pref_default_mode'), trailing: (): void => { this.modeTrailing() } })
    SettingRow({ title: $r('app.string.pref_default_effect'), showDivider: true, trailing: (): void => { this.effectTrailing() } })
    SettingRow({ title: $r('app.string.pref_default_target'), showDivider: true, trailing: (): void => { this.targetTrailing() } })
  }

  @Builder
  emojiListBlock() {
    Column() {
      Row() {
        Text($r('app.string.pref_emoji_list'))
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%').alignItems(VerticalAlign.Center)

      // 当前列表：每个 emoji 一个芯片，右上角小叉可删除。
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.vm.emojiPalette, (e: string, index: number) => {
          Stack({ alignContent: Alignment.TopEnd }) {
            Text(e)
              .fontSize(24)
              .width(44).height(44)
              .textAlign(TextAlign.Center)
              .borderRadius(12)
              .backgroundColor($r('app.color.surface_2'))
            Text('✕')
              .fontSize(11)
              .fontColor(Color.White)
              .width(18).height(18)
              .textAlign(TextAlign.Center)
              .borderRadius(9)
              .backgroundColor($r('app.color.danger'))
              .onClick(() => this.vm.removeEmojiAt(index))
          }
          .margin({ right: 10, top: 10 })
        }, (e: string, index: number) => `${index}_${e}`)
      }
      .width('100%')

      // 添加：独立输入框 + 添加按钮，点击即刻把表情追加到列表并保存。
      Row() {
        TextInput({ text: this.addText, placeholder: $r('app.string.emoji_add_hint') })
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.surface_2'))
          .borderRadius(12)
          .onChange((v: string) => { this.addText = v; })
        Button({ type: ButtonType.Capsule, stateEffect: true }) {
          Text($r('app.string.action_add')).fontSize($r('app.float.font_caption')).fontColor($r('app.color.on_brand'))
        }
        .height(44).backgroundColor($r('app.color.brand')).padding({ left: 18, right: 18 }).margin({ left: 10 })
        .onClick(() => {
          this.vm.addEmojis(this.addText);
          this.addText = '';
        })
      }
      .width('100%').margin({ top: 14 }).alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  @Builder
  emojiFontContent() {
    this.emojiListBlock()
    this.fontListBlock()
  }

  /** 字体管理：默认字体 + 已导入字体，可选择(打勾)、删除，并支持新增。 */
  @Builder
  fontListBlock() {
    Column() {
      Row() {
        Text($r('app.string.pref_emoji_font'))
          .fontSize($r('app.float.font_body'))
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        this.fontTrailing()
      }
      .width('100%').alignItems(VerticalAlign.Center)

      ForEach(this.vm.fonts, (path: string) => {
        Row() {
          Text(path === DEFAULT_FONT_MARKER ? $r('app.string.pref_default_font') : this.fontFileName(path))
            .fontSize($r('app.float.font_caption'))
            .fontColor(path === this.vm.selectedFont ? $r('app.color.brand') : $r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (path === this.vm.selectedFont) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([$r('app.color.brand')])
          }
          if (path !== DEFAULT_FONT_MARKER) {
            Button({ type: ButtonType.Circle, stateEffect: true }) {
              SymbolGlyph($r('sys.symbol.trash')).fontSize(16).fontColor([$r('app.color.danger')])
            }
            .width(40).height(40).backgroundColor($r('app.color.surface_2')).margin({ left: 10 })
            .onClick(() => this.vm.removeFont(path))
          }
        }
        .width('100%').height(44).alignItems(VerticalAlign.Center)
        .onClick(() => this.vm.selectFont(path))
      }, (path: string, i: number) => `${i}_${path}`)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  @Builder
  privacyContent() {
    SettingRow({
      title: $r('app.string.privacy_offline_title'),
      subtitle: $r('app.string.privacy_offline_desc')
    })
  }

  @Builder
  aboutContent() {
    SettingRow({ title: $r('app.string.about_version'), valueText: this.vm.appVersion })
    SettingRow({
      title: $r('app.string.about_github'),
      subtitle: $r('app.string.about_github_sub'),
      showChevron: true,
      showDivider: true,
      onClickRow: (): void => { this.openGithub(); }
    })
    SettingRow({
      title: $r('app.string.about_license'),
      showChevron: true,
      showDivider: true,
      onClickRow: (): void => { this.showLicense(); }
    })
  }

  /** 在系统浏览器打开开源仓库地址。 */
  private openGithub(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ctx.openLink(AppConstants.GITHUB_URL, { appLinkingOnly: false })
      .catch((e: Object): void => {
        Logger.warn('SettingsPage', 'open github failed');
        this.getUIContext().getPromptAction().showToast({
          message: this.getUIContext().getHostContext()!.resourceManager.getStringByNameSync('about_open_failed'),
          duration: 2000
        });
      });
  }

  /** 展示开源许可与署名(满足 AGPL-3.0 / ONNX Runtime 的署名要求)。 */
  private showLicense(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: $r('app.string.about_license_title'),
      message: $r('app.string.about_license_content'),
      buttons: [
        { text: $r('app.string.action_done'), color: $r('app.color.brand') }
      ]
    }).catch((): void => {});
  }

  @Builder
  topBar() {
    Row() {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(24).fontColor([$r('app.color.text_primary')])
      }
      .width(40).height(40).backgroundColor(Color.Transparent)
      .onClick(() => this.pathStack.pop())

      Text($r('app.string.settings_title'))
        .fontSize($r('app.float.font_title'))
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 4 })
      Blank()
    }
    .width('100%').height(52 + this.safe.top).padding({ left: 8, right: 8, top: this.safe.top }).alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      this.topBar()
      Scroll() {
        Column() {
          SettingsSection({ title: $r('app.string.pref_theme_mode'), content: (): void => { this.appearanceContent() } })
          SettingsSection({ title: $r('app.string.group_mask_pref'), content: (): void => { this.maskPrefContent() } })
          SettingsSection({ title: $r('app.string.group_emoji_font'), content: (): void => { this.emojiFontContent() } })
          SettingsSection({ title: $r('app.string.group_privacy'), content: (): void => { this.privacyContent() } })
          SettingsSection({ title: $r('app.string.group_about'), content: (): void => { this.aboutContent() } })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: this.safe.bottom + 24 })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
