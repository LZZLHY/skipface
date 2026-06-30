/**
 * SafeAreaModel.ets
 * 分层：common / 安全区
 *
 * 职责：可观察的"系统安全区内边距"模型(状态管理 V2)。应用开启全屏沉浸式布局后，
 *       由 UIAbility 计算状态栏(顶部)与导航条/手势区(底部)的避让高度(单位 vp)写入本模型，
 *       页面以 @Local 连接，并据此给内容加 top/bottom 内边距，使背景铺满全屏、内容不被遮挡。
 *
 * 说明：@ComponentV2 不支持 @StorageProp，故用 AppStorageV2 承载 @ObservedV2 单例。
 */
import { AppStorageV2 } from '@kit.ArkUI';

@ObservedV2
export class SafeAreaModel {
  /** 顶部安全区(状态栏)高度，单位 vp。 */
  @Trace top: number = 0;
  /** 底部安全区(导航条/手势指示)高度，单位 vp。 */
  @Trace bottom: number = 0;

  /** 获取全局单例。 */
  static instance(): SafeAreaModel {
    return AppStorageV2.connect<SafeAreaModel>(
      SafeAreaModel, 'safeAreaModel', (): SafeAreaModel => new SafeAreaModel()
    )!;
  }
}
