/**
 * ThemePalette.ets
 * 分层：common / 主题
 *
 * 职责：进阶"动态换肤"用的可观察主题色调色板（可选能力）。
 *  - 基础换肤：直接改 element/color.json 的 brand 系列即可，无需本类。
 *  - 动态换肤：当需要让用户在运行时切换强调色时，UI 读取本调色板而非静态资源，
 *    切换预设时整体替换字段，@Trace 触发订阅组件重渲染。
 *
 * 注意：每个预设都应提供与浅/深背景足够的对比度（正文 AA ≥ 4.5:1）。
 */
import { AppStorageV2 } from '@kit.ArkUI';

/** 一个强调色预设：包含主色、浅底、深色变体与其上的前景色。 */
export interface BrandPreset {
  /** 预设标识。 */
  id: string;
  /** 主强调色。 */
  brand: string;
  /** 强调色浅底（选中底/标签底）。 */
  brandSoft: string;
  /** 强调色深变体（强调文本）。 */
  brandDeep: string;
  /** 强调色之上的前景（通常为白/近黑）。 */
  onBrand: string;
}

/** 内置预设色板。 */
export class BrandPresets {
  static readonly INDIGO: BrandPreset = {
    id: 'indigo', brand: '#5B6CFF', brandSoft: '#ECEEFF', brandDeep: '#3D4ED6', onBrand: '#FFFFFF'
  };
  static readonly TEAL: BrandPreset = {
    id: 'teal', brand: '#12B488', brandSoft: '#E2F6EF', brandDeep: '#0C8A68', onBrand: '#FFFFFF'
  };
  static readonly CORAL: BrandPreset = {
    id: 'coral', brand: '#FF6B6B', brandSoft: '#FFEAEA', brandDeep: '#D94C4C', onBrand: '#FFFFFF'
  };

  /** 全部预设列表，供设置页展示。 */
  static readonly ALL: BrandPreset[] = [BrandPresets.INDIGO, BrandPresets.TEAL, BrandPresets.CORAL];

  /** 按 id 查找预设，未命中回退到 INDIGO。 */
  static byId(id: string): BrandPreset {
    return BrandPresets.ALL.find((p: BrandPreset): boolean => p.id === id) ?? BrandPresets.INDIGO;
  }

  private constructor() {}
}

/**
 * 可观察的当前主题色。通过 AppStorageV2 持久驻留，跨页面共享。
 * UI 中以 `themePalette.brand` 等读取（动态换肤）；若不启用换肤，可直接用资源色。
 */
@ObservedV2
export class ThemePalette {
  @Trace brand: string = BrandPresets.INDIGO.brand;
  @Trace brandSoft: string = BrandPresets.INDIGO.brandSoft;
  @Trace brandDeep: string = BrandPresets.INDIGO.brandDeep;
  @Trace onBrand: string = BrandPresets.INDIGO.onBrand;
  @Trace presetId: string = BrandPresets.INDIGO.id;

  /** 应用一个预设到当前调色板。 */
  applyPreset(preset: BrandPreset): void {
    this.brand = preset.brand;
    this.brandSoft = preset.brandSoft;
    this.brandDeep = preset.brandDeep;
    this.onBrand = preset.onBrand;
    this.presetId = preset.id;
  }

  /** 获取全局单例（懒创建）。 */
  static instance(): ThemePalette {
    return AppStorageV2.connect<ThemePalette>(ThemePalette, 'themePalette', (): ThemePalette => new ThemePalette())!;
  }
}
