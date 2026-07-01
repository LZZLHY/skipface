/**
 * CoreVisionFaceDetector.ets
 * 分层：capability / 推理能力（系统视觉服务实现）
 *
 * 职责：FaceDetector 的可选实现（系统视觉服务）。基于 HarmonyOS 系统自带的 Core Vision Kit
 *       (@kit.CoreVisionKit faceDetector)，完全本地、离线、免模型文件：
 *   - load()   = faceDetector.init() 一次性初始化分析器；
 *   - detect() = faceDetector.detect(pixelMap) 直接返回人脸框/姿态/关键点；
 *   - release()= faceDetector.release() 释放分析器。
 *
 * 选型理由：完全本地、离线、免模型文件，随系统升级而优化，满足"隐私优先、纯本地"的
 *   产品定位；且系统服务运行于独立进程，不在应用进程内加载第三方原生推理库，规避了
 *   进程内原生推理崩溃(SIGABRT)的风险。设计文档 §12 已将"系统视觉服务"列为 FaceDetector
 *   的合法实现。
 *
 * 坐标系：detect 返回的 rect/points 均为传入 PixelMap（即代理显示图）的像素坐标，
 *   与上层编辑坐标系一致，无需额外换算。
 *
 * 关键点策略：系统接口提供人脸框与三维姿态(yaw/pitch/roll)。本实现用 rect + roll
 *   合成 5 关键点（双眼/鼻/双嘴角），使 Emoji/模糊能跟随头部倾斜(roll)旋转；
 *   合成方式保证 landmarks.eyeAngleDeg == roll。
 */
import { faceDetector } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { FaceDetector } from './FaceDetector';
import { FaceDetection, FaceLandmarks } from '../../domain/model/FaceDetection';
import { PointF, RectF } from '../../domain/model/Geometry';
import { AppConstants } from '../../common/constants/AppConstants';
import { Logger } from '../../common/utils/Logger';

/** 系统人脸检测能力的 SysCap 名，用于运行期能力查询(降级)。 */
const FACE_DETECTOR_SYSCAP: string = 'SystemCapability.AI.Face.Detector';

export class CoreVisionFaceDetector implements FaceDetector {
  private static readonly TAG: string = 'CoreVisionDetector';

  private initialized: boolean = false;
  private loadingPromise: Promise<void> | null = null;
  /** 自增序号，配合时间戳生成稳定且唯一的检测 id。 */
  private seq: number = 0;

  isLoaded(): boolean {
    return this.initialized;
  }

  /** 幂等初始化：并发调用复用同一个 loadingPromise。 */
  async load(): Promise<void> {
    if (this.initialized) {
      return;
    }
    if (!canIUse(FACE_DETECTOR_SYSCAP)) {
      // 设备不具备系统人脸检测能力：标记为已加载，detect 返回空(用户可手动添加)。
      Logger.warn(CoreVisionFaceDetector.TAG, 'face detector syscap unavailable');
      this.initialized = true;
      return;
    }
    if (this.loadingPromise) {
      return this.loadingPromise;
    }
    this.loadingPromise = this.doLoad();
    try {
      await this.loadingPromise;
    } finally {
      this.loadingPromise = null;
    }
  }

  private async doLoad(): Promise<void> {
    const start: number = Date.now();
    try {
      await faceDetector.init();
      this.initialized = true;
      Logger.info(CoreVisionFaceDetector.TAG, `analyzer initialized in ${Date.now() - start}ms`);
    } catch (e) {
      // 初始化失败不抛出：降级为"无自动检测"，应用仍可手动添加遮挡。
      this.initialized = true;
      Logger.error(CoreVisionFaceDetector.TAG, 'init failed, fallback to manual', e as Error);
    }
  }

  /**
   * 对代理图执行人脸检测。
   * @param pixelMap 代理显示图(像素坐标即编辑坐标)。
   * @returns 代理图坐标系下、已按置信度过滤的检测结果。
   */
  async detect(pixelMap: image.PixelMap): Promise<FaceDetection[]> {
    if (!this.initialized) {
      await this.load();
    }
    if (!canIUse(FACE_DETECTOR_SYSCAP)) {
      return [];
    }
    let faces: faceDetector.Face[] = [];
    try {
      const visionInfo: faceDetector.VisionInfo = { pixelMap };
      faces = await faceDetector.detect(visionInfo);
    } catch (e) {
      // 检测失败(如格式不支持/服务异常)时不阻断流程，返回空让用户手动添加。
      Logger.error(CoreVisionFaceDetector.TAG, 'detect failed', e as Error);
      return [];
    }

    const result: FaceDetection[] = [];
    for (let i: number = 0; i < faces.length; i++) {
      const f: faceDetector.Face = faces[i];
      // probability 理论上恒有值；做兜底避免个别机型字段缺失时因 undefined 比较而全量丢弃。
      const prob: number = typeof f.probability === 'number' ? f.probability : 1;
      if (prob < AppConstants.SCORE_THRESHOLD) {
        continue;
      }
      const r: faceDetector.FaceRectangle = f.rect;
      const box: RectF = new RectF(r.left, r.top, r.left + r.width, r.top + r.height);
      // roll：绕 Z 轴的头部倾斜角(度)，直接作为遮挡旋转角。
      const roll: number = f.pose ? f.pose.roll : 0;
      const landmarks: FaceLandmarks = CoreVisionFaceDetector.synthesizeLandmarks(box, roll);
      const id: string = `det_${Date.now().toString(36)}_${this.seq++}`;
      result.push(new FaceDetection(id, box, landmarks, prob));
    }
    Logger.info(CoreVisionFaceDetector.TAG, `detected ${result.length} face(s)`);
    return result;
  }

  async release(): Promise<void> {
    if (!this.initialized || !canIUse(FACE_DETECTOR_SYSCAP)) {
      this.initialized = false;
      return;
    }
    try {
      await faceDetector.release();
    } catch (e) {
      Logger.warn(CoreVisionFaceDetector.TAG, 'release failed');
    }
    this.initialized = false;
    this.loadingPromise = null;
  }

  /**
   * 由人脸框 + 头部 roll 合成 5 关键点。
   *
   * 数学约定：先在"未旋转"的人脸框内按经验比例摆放 5 点，再整体绕框中心
   *   旋转 roll 度(屏幕坐标系，y 向下，顺时针为正，与 Canvas.rotate 一致)。
   *   由于双眼相对框中心左右对称，旋转后二者连线角度恰等于 roll，
   *   因此 landmarks.eyeAngleDeg == roll，遮挡可自然跟随头部倾斜。
   */
  private static synthesizeLandmarks(box: RectF, rollDeg: number): FaceLandmarks {
    const cx: number = box.centerX;
    const cy: number = box.centerY;
    const w: number = box.width;
    const h: number = box.height;
    const rad: number = (rollDeg * Math.PI) / 180;
    const cos: number = Math.cos(rad);
    const sin: number = Math.sin(rad);
    // 绕框中心旋转一个点。
    const rot = (px: number, py: number): PointF => {
      const dx: number = px - cx;
      const dy: number = py - cy;
      return new PointF(cx + dx * cos - dy * sin, cy + dx * sin + dy * cos);
    };
    return new FaceLandmarks(
      rot(cx - 0.19 * w, cy - 0.18 * h), // 左眼
      rot(cx + 0.19 * w, cy - 0.18 * h), // 右眼
      rot(cx, cy + 0.02 * h),            // 鼻尖
      rot(cx - 0.15 * w, cy + 0.26 * h), // 左嘴角
      rot(cx + 0.15 * w, cy + 0.26 * h)  // 右嘴角
    );
  }
}
