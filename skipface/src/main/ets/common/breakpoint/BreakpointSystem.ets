/**
 * BreakpointSystem.ets
 * 分层：common / 响应式断点
 *
 * 职责：通过 UIContext 的 MediaQuery 监听窗口宽度变化，计算当前断点(sm/md/lg)并写入
 *       可观察的 BreakpointModel，供各页面以 @Local + AppStorageV2 消费。
 *
 * 用法：在根组件 aboutToAppear 中调用 register(this.getUIContext())；
 *       在 aboutToDisappear 中调用 unregister()。
 */
import { mediaquery, UIContext } from '@kit.ArkUI';
import { WidthBreakpoint, BreakpointBounds } from './BreakpointType';
import { BreakpointModel } from './BreakpointModel';

export class BreakpointSystem {
  private mdListener?: mediaquery.MediaQueryListener;
  private lgListener?: mediaquery.MediaQueryListener;
  private smListener?: mediaquery.MediaQueryListener;

  /**
   * 注册媒体查询监听。
   * @param uiContext 当前 UIContext(组件中通过 this.getUIContext() 获取)。
   */
  register(uiContext: UIContext): void {
    const mq = uiContext.getMediaQuery();

    // md：宽度落在 [600vp, 840vp)
    this.mdListener = mq.matchMediaSync(
      `(${BreakpointBounds.MD_MIN}vp<=width) and (width<${BreakpointBounds.LG_MIN}vp)`
    );
    this.mdListener.on('change', (res: mediaquery.MediaQueryResult): void => {
      if (res.matches) {
        BreakpointSystem.update(WidthBreakpoint.MD);
      }
    });

    // lg：宽度 >= 840vp
    this.lgListener = mq.matchMediaSync(`(${BreakpointBounds.LG_MIN}vp<=width)`);
    this.lgListener.on('change', (res: mediaquery.MediaQueryResult): void => {
      if (res.matches) {
        BreakpointSystem.update(WidthBreakpoint.LG);
      }
    });

    // sm：宽度 < 600vp（兜底）
    this.smListener = mq.matchMediaSync(`(width<${BreakpointBounds.MD_MIN}vp)`);
    this.smListener.on('change', (res: mediaquery.MediaQueryResult): void => {
      if (res.matches) {
        BreakpointSystem.update(WidthBreakpoint.SM);
      }
    });

    // 应用初始断点：mediaquery 监听仅在"跨越边界"时回调，启动时不会触发。
    // 这里主动读取各监听器当前的 matches 评估一次初始断点，
    // 否则大屏(平板/2in1/折叠展开)冷启动会停留在 SM 单栏布局。
    this.applyInitial();
  }

  /** 启动时按当前匹配状态确定初始断点(lg 优先，其次 md，否则 sm)。 */
  private applyInitial(): void {
    if (this.lgListener?.matches) {
      BreakpointSystem.update(WidthBreakpoint.LG);
    } else if (this.mdListener?.matches) {
      BreakpointSystem.update(WidthBreakpoint.MD);
    } else {
      BreakpointSystem.update(WidthBreakpoint.SM);
    }
  }

  /** 注销所有监听，释放资源。 */
  unregister(): void {
    this.mdListener?.off('change');
    this.lgListener?.off('change');
    this.smListener?.off('change');
    this.mdListener = undefined;
    this.lgListener = undefined;
    this.smListener = undefined;
  }

  /** 写入可观察断点模型，触发订阅组件刷新。 */
  private static update(bp: WidthBreakpoint): void {
    BreakpointModel.instance().current = bp;
  }
}
