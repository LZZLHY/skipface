/**
 * BreakpointModel.ets
 * 分层：common / 响应式断点
 *
 * 职责：可观察的当前断点模型(状态管理 V2)。@ComponentV2 不支持 @StorageProp，
 *       因此用 AppStorageV2 承载一个 @ObservedV2 对象，页面以 @Local 连接并读取 .current。
 */
import { AppStorageV2 } from '@kit.ArkUI';
import { WidthBreakpoint } from './BreakpointType';

@ObservedV2
export class BreakpointModel {
  /** 当前宽度断点。 */
  @Trace current: WidthBreakpoint = WidthBreakpoint.SM;

  /** 获取全局单例。 */
  static instance(): BreakpointModel {
    return AppStorageV2.connect<BreakpointModel>(
      BreakpointModel, 'breakpointModel', (): BreakpointModel => new BreakpointModel()
    )!;
  }
}
