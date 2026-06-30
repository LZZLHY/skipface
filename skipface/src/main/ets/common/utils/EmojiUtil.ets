/**
 * EmojiUtil.ets
 * 分层：common / 工具
 *
 * 职责：把用户输入的"连续 emoji 字符串"拆分为单个可见 emoji（字素簇近似）。
 *       一个可见 emoji 可能由多个 Unicode 码位组成（ZWJ 序列、肤色修饰、变体选择符、
 *       区域指示符等）。本实现先按码位切分，再把"修饰/连接"类码位并入前一个 emoji。
 *
 * 说明：ArkTS 不支持 Intl.Segmenter，这里用码位迭代 + 合并规则实现，足够覆盖常见 emoji。
 */
export class EmojiUtil {
  /** 零宽连接符。 */
  private static readonly ZWJ: number = 0x200d;
  /** 变体选择符 16(emoji 呈现)。 */
  private static readonly VS16: number = 0xfe0f;

  /** 是否为"应并入前一个 emoji"的修饰类码位。 */
  private static isCombining(code: number): boolean {
    // 肤色修饰符 Fitzpatrick
    if (code >= 0x1f3fb && code <= 0x1f3ff) {
      return true;
    }
    // 变体选择符
    if (code === EmojiUtil.VS16) {
      return true;
    }
    // 组合用记号
    if (code >= 0x20d0 && code <= 0x20ff) {
      return true;
    }
    return false;
  }

  /** 是否为区域指示符(国旗由两个区域指示符成对组成)。 */
  private static isRegionalIndicator(code: number): boolean {
    return code >= 0x1f1e6 && code <= 0x1f1ff;
  }

  /** 将字符串拆分为 emoji 数组，过滤空白项。 */
  static split(text: string): string[] {
    if (!text) {
      return [];
    }
    // 第一步：按"码位"切分。关键：不能依赖 Array.from / for-of，
    // 因为不同 ArkTS 运行时上它们可能按 UTF-16 码元迭代，会把 emoji 的代理对(surrogate
    // pair)拆成两个孤立半码元(渲染成豆腐块 �)。这里用 charCodeAt 手动识别并保留完整代理对。
    const units: string[] = [];
    for (let i: number = 0; i < text.length; i++) {
      const c: number = text.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length) {
        const n: number = text.charCodeAt(i + 1);
        if (n >= 0xdc00 && n <= 0xdfff) {
          units.push(text.substring(i, i + 2)); // 完整代理对作为一个码位
          i++;
          continue;
        }
      }
      units.push(text.charAt(i));
    }
    // 第二步：把"修饰/连接"类码位并入前一个 emoji(ZWJ 序列、肤色、变体选择符、国旗等)。
    const result: string[] = [];
    let lastWasZwj: boolean = false;
    // 上一个推入的元素是否为"落单的区域指示符"，等待与下一个配对成国旗。
    let pendingRegional: boolean = false;
    for (const ch of units) {
      const code: number = ch.codePointAt(0) ?? 0;

      // 区域指示符成对组成国旗：落单时先入列，遇到下一个区域指示符再配对，
      // 避免把三面及以上相邻国旗错误地全部并入同一项。
      if (EmojiUtil.isRegionalIndicator(code)) {
        if (pendingRegional && result.length > 0) {
          result[result.length - 1] = result[result.length - 1] + ch;
          pendingRegional = false;
        } else {
          result.push(ch);
          pendingRegional = true;
        }
        lastWasZwj = false;
        continue;
      }
      pendingRegional = false;

      const isZwj: boolean = code === EmojiUtil.ZWJ;
      const mergeIntoPrev: boolean = result.length > 0 && (isZwj || lastWasZwj || EmojiUtil.isCombining(code));
      if (mergeIntoPrev) {
        result[result.length - 1] = result[result.length - 1] + ch;
      } else if (ch.trim().length > 0) {
        result.push(ch);
      }
      lastWasZwj = isZwj;
    }
    return result;
  }

  /** 把 emoji 数组拼回字符串（用于编辑框回填）。 */
  static join(list: string[]): string {
    return list.join('');
  }

  private constructor() {}
}
