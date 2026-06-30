/**
 * OnnxFaceDetector.ets
 * 分层：capability / 推理能力（ONNX Runtime 实现，默认）
 *
 * 职责：FaceDetector 的默认实现。基于 OpenHarmony TPC 的 @ohos/onnxruntime（ONNX Runtime
 *       NAPI 移植），直接加载 rawfile 中的 YOLOv8-face ONNX 权重并在端侧本地推理：
 *   - load()   = 初始化 ORT 全局环境 → 从 rawfile 读取 .onnx 字节 → 创建会话 → 一次 warmup；
 *   - detect() = Letterbox 预处理 → 构造 FLOAT 张量 → session.Run → DetectionDecoder 后处理；
 *   - release()= 关闭会话并置空引用。
 *
 * 选型理由：与上游 Android 工程一致使用 ONNX Runtime + YOLOv8-face 权重，免离线模型转换、
 *   开箱即用，且提供 5 关键点（双眼/鼻/双嘴角）以驱动遮挡跟随头部倾斜旋转。完全本地、离线，
 *   符合"隐私优先、纯本地"的产品定位。
 *
 * 模型契约（YOLOv8n-face，Ultralytics 导出）：
 *   - 输入：名 "images"，形状 [1,3,640,640] Float32，CHW，归一化 0~1，letterbox 灰填充；
 *   - 输出：名 "output0"，形状 [1,20,8400]（通道优先）：0~3=cx,cy,w,h；4=score；5~19=5 关键点(x,y,conf)。
 *   实际推理时输入/输出名通过会话动态查询，不写死。
 *
 * 坐标系：detect 返回 PixelMap（代理显示图）像素坐标系下的结果，与编辑坐标系一致。
 *
 * 线程与资源：ORT 原生会话为底层资源，release() 时显式 Close()；张量/结果在每次 detect 内即用即放。
 * 设备约束：随包仅提供 arm64-v8a 原生库；非 arm64 环境（如 x86 模拟器）会话创建会失败，
 *   此时优雅降级为"无自动检测"（返回空），用户仍可手动添加遮挡。
 *
 * ⚠️ 已知稳定性问题：在部分机型/系统版本上，`@ohos/onnxruntime` 这个 TPC NAPI 移植会在
 *   多次调用 `session.Run` 后于原生层抛出 C++ 异常（std::length_error）并逸出 NAPI 边界，
 *   直接 abort 整个进程（SIGABRT），ArkTS 的 try/catch 无法拦截。表现为"反复进出编辑器
 *   若干次后随机崩溃"。因此本实现**默认不启用**，`AppContainer` 默认使用
 *   `CoreVisionFaceDetector`（系统服务，独立进程，无此风险）。仅在确认目标机型上 ORT 稳定、
 *   或对 YOLOv8 关键点精度有强需求时再切回本实现。
 */
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import * as ort from '@ohos/onnxruntime';
import { FaceDetector } from './FaceDetector';
import { Letterbox, LetterboxResult } from './Letterbox';
import { DetectionDecoder } from './DetectionDecoder';
import { FaceDetection } from '../../domain/model/FaceDetection';
import { AppConstants } from '../../common/constants/AppConstants';
import { Logger } from '../../common/utils/Logger';

/** ORT 全局环境是否已初始化（进程级，只需一次）。 */
let gEnvInitialized: boolean = false;

export class OnnxFaceDetector implements FaceDetector {
  private static readonly TAG: string = 'OnnxFaceDetector';

  private readonly context: common.Context;
  private session: ort.OnnxSession | null = null;
  /**
   * 模型字节缓冲：必须在 session 整个生命周期内保持强引用。
   * 关键：CreateSessionFromBuffer 直接引用该缓冲(不一定深拷贝)，若被 GC 回收，
   * 后续 session.Run 会读到被释放/复用的模型内存，抛出 std::length_error 等原生异常
   * 并使整个进程 abort(SIGABRT)。表现为"多跑几次后随机崩溃"(与 GC 时机相关)。
   */
  private modelData: Int8Array | null = null;
  private inputName: string = 'images';
  private loadingPromise: Promise<void> | null = null;
  /** 加载失败标记：失败后 detect 直接返回空，避免反复重试。 */
  private failed: boolean = false;
  /** 最近一次加载失败的原因（用于 UI 诊断展示）。 */
  private lastError: string = '';

  /** @param context 用于访问 resourceManager 读取 rawfile 模型。 */
  constructor(context: common.Context) {
    this.context = context;
  }

  isLoaded(): boolean {
    return this.session !== null;
  }

  /** 幂等加载：并发调用复用同一个 loadingPromise。 */
  async load(): Promise<void> {
    if (this.session || this.failed) {
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
      // 1) 初始化 ORT 全局环境（进程级，仅一次）。
      if (!gEnvInitialized) {
        ort.OnnxEnvironment.InitEnvironment();
        gEnvInitialized = true;
        Logger.info(OnnxFaceDetector.TAG, `ORT version ${ort.OnnxEnvironment.GetVersion()}`);
      }

      // 2) 读取 rawfile 中的 .onnx 字节，转为 Int8Array（会话从内存缓冲创建）。
      const raw: Uint8Array =
        await this.context.resourceManager.getRawFileContent(AppConstants.ONNX_MODEL_FILE_NAME);
      const modelBytes: Int8Array = new Int8Array(raw.buffer, raw.byteOffset, raw.byteLength);
      // 关键：在创建会话前就持有强引用，并在 session 生命周期内一直保留，
      // 防止该缓冲被 GC 回收导致 Run 读到已释放的模型内存而原生崩溃。
      this.modelData = modelBytes;

      // 3) 配置会话：开启全部图优化，限制线程数以兼顾功耗与时延。
      const options: ort.OnnxSessionOptions = new ort.OnnxSessionOptions();
      options.SetOptimizationLevel(ort.OnnxOptimizationLevel.ALL);
      options.SetIntraOpNumThreads(2);
      this.session = ort.OnnxEnvironment.CreateSessionFromBufferWithOptions(modelBytes, options);
      options.Close();

      // 4) 记录真实输入名（动态查询，避免写死）。
      const inputNames: string[] = this.session.GetInputNames();
      if (inputNames.length > 0) {
        this.inputName = inputNames[0];
      }
      Logger.info(OnnxFaceDetector.TAG, `model loaded in ${Date.now() - start}ms, input=${this.inputName}`);

      // 5) warmup：用全零张量跑一次，触发内存分配与图执行路径。
      await this.warmup();
    } catch (e) {
      // 加载失败（如非 arm64 设备无原生库）：标记失败并记录原因，便于 UI 诊断。
      this.session = null;
      this.modelData = null;
      this.failed = true;
      const err: Error = e as Error;
      this.lastError = `${err.name}: ${err.message}`;
      Logger.error(OnnxFaceDetector.TAG, 'load model failed', err);
    }
  }

  /** 暴露最近一次加载失败原因（无则空串）。 */
  getLastError(): string {
    return this.lastError;
  }

  /** 用零张量预热会话。 */
  private warmup(): void {
    const session: ort.OnnxSession | null = this.session;
    if (!session) {
      return;
    }
    const S: number = AppConstants.MODEL_INPUT_SIZE;
    const buf: ArrayBuffer = new ArrayBuffer(3 * S * S * Float32Array.BYTES_PER_ELEMENT);
    const tensor: ort.OnnxTensor = new ort.OnnxTensor(buf, [1, 3, S, S], ort.OnnxArkTSType.FLOAT);
    const inputs: Record<string, ort.OnnxValue> = {};
    inputs[this.inputName] = tensor;
    const ws: number = Date.now();
    try {
      const result: ort.OnnxResult = session.Run(inputs);
      result.Close();
      Logger.info(OnnxFaceDetector.TAG, `warmup done in ${Date.now() - ws}ms`);
    } catch (e) {
      Logger.warn(OnnxFaceDetector.TAG, 'warmup failed');
    } finally {
      tensor.Close();
    }
  }

  /**
   * 对代理图执行人脸检测。
   * @param pixelMap 代理显示图（像素坐标即编辑坐标）。
   * @returns 代理图坐标系下、已置信度过滤并 NMS 的检测结果；失败时返回空。
   */
  async detect(pixelMap: image.PixelMap): Promise<FaceDetection[]> {
    if (!this.session && !this.failed) {
      await this.load();
    }
    const session: ort.OnnxSession | null = this.session;
    if (!session) {
      // 模型不可用(如非 arm64 设备无原生库、或加载失败)：优雅降级为"无自动检测"，
      // 返回空列表让用户手动添加遮挡，而非把技术错误抛给上层/用户。
      Logger.warn(OnnxFaceDetector.TAG, `model unavailable, skip detection: ${this.lastError || 'not loaded'}`);
      return [];
    }

    // 1) 预处理（letterbox + 归一化 + CHW）。
    const pre: LetterboxResult = await Letterbox.preprocess(pixelMap);
    const S: number = AppConstants.MODEL_INPUT_SIZE;

    // 2) 构造输入张量并推理（张量/结果用后即放）。
    const tensor: ort.OnnxTensor = new ort.OnnxTensor(pre.buffer, [1, 3, S, S], ort.OnnxArkTSType.FLOAT);
    const inputs: Record<string, ort.OnnxValue> = {};
    inputs[this.inputName] = tensor;

    let detections: FaceDetection[] = [];
    const infStart: number = Date.now();
    try {
      const result: ort.OnnxResult = session.Run(inputs);
      try {
        // 3) 取首个输出并解码。
        const outNames: string[] = session.GetOutputNames();
        const value: ort.OnnxValue = result.GetValueByName(outNames[0]);
        try {
          if (value.GetType() === ort.OnnxValueType.TENSOR) {
            const outTensor: ort.OnnxTensor = value as ort.OnnxTensor;
            const outData: Float32Array = new Float32Array(outTensor.GetDataAsArrayBuffer());
            detections = DetectionDecoder.decode(outData, pre.scale, pre.padX, pre.padY);
          }
        } finally {
          // 关闭输出值，释放其底层原生张量。否则每次推理累积一份原生内存，多次后 OOM。
          try {
            value.Close();
          } catch (closeErr) {
            // 若已被 result 关闭则忽略。
          }
        }
      } finally {
        result.Close();
      }
      Logger.info(OnnxFaceDetector.TAG, `inference ${Date.now() - infStart}ms, ${detections.length} face(s)`);
    } catch (e) {
      // 单次推理失败不阻断流程，返回空让用户手动添加。
      Logger.error(OnnxFaceDetector.TAG, 'inference failed', e as Error);
      detections = [];
    } finally {
      tensor.Close();
    }
    return detections;
  }

  async release(): Promise<void> {
    const session: ort.OnnxSession | null = this.session;
    this.session = null;
    this.loadingPromise = null;
    if (session) {
      try {
        session.Close();
      } catch (e) {
        Logger.warn(OnnxFaceDetector.TAG, 'release failed');
      }
    }
    // 会话关闭后再释放模型缓冲引用(此前必须一直保留，见字段注释)。
    this.modelData = null;
  }
}
