/**
 * MindSporeFaceDetector.ets
 * 分层：capability / 推理能力（MindSpore Lite 实现）
 *
 * 职责：FaceDetector 的可选实现（系统 MindSpore Lite）。基于系统 MindSpore Lite Kit：
 *   - 从 rawfile 读取 .ms 模型并加载为会话；
 *   - 启动时做一次 warmup，消除首帧抖动；
 *   - detect() = Letterbox 预处理 → predict 推理 → DetectionDecoder 后处理。
 *
 * 线程：MindSpore Lite 的 predict 为异步；本类对外暴露 Promise，可在任意上下文 await。
 * 资源：模型与张量为底层资源，release() 时置空引用以便 GC/底层回收。
 */
import { mindSporeLite } from '@kit.MindSporeLiteKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { FaceDetector } from './FaceDetector';
import { Letterbox, LetterboxResult } from './Letterbox';
import { DetectionDecoder } from './DetectionDecoder';
import { FaceDetection } from '../../domain/model/FaceDetection';
import { AppConstants } from '../../common/constants/AppConstants';
import { Logger } from '../../common/utils/Logger';

export class MindSporeFaceDetector implements FaceDetector {
  private static readonly TAG: string = 'MindSporeDetector';

  private readonly context: common.Context;
  private model: mindSporeLite.Model | null = null;
  /**
   * 模型字节缓冲：必须在 model 整个生命周期内保持强引用。
   * 与 OnnxFaceDetector 同理——loadModelFromBuffer 可能直接引用该缓冲而非深拷贝，
   * 若被 GC 回收，后续 predict 会读到已释放内存而原生崩溃(SIGABRT)。
   */
  private modelData: ArrayBuffer | null = null;
  private loadingPromise: Promise<void> | null = null;

  /** @param context 用于访问 resourceManager 读取 rawfile 模型。 */
  constructor(context: common.Context) {
    this.context = context;
  }

  isLoaded(): boolean {
    return this.model !== null;
  }

  /** 幂等加载：并发调用复用同一个 loadingPromise。 */
  async load(): Promise<void> {
    if (this.model) {
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
      // 1) 读取 rawfile 模型字节。
      const raw: Uint8Array = await this.context.resourceManager.getRawFileContent(AppConstants.MS_MODEL_FILE_NAME);
      const modelBuffer: ArrayBuffer = raw.buffer.slice(raw.byteOffset, raw.byteOffset + raw.byteLength);
      // 关键：在加载前持有强引用，并在 model 生命周期内保留，防止缓冲被 GC 回收导致 predict 原生崩溃。
      this.modelData = modelBuffer;

      // 2) 构造推理上下文：优先 CPU，多线程；设备允许时可扩展 NNRT/NPU。
      const msContext: mindSporeLite.Context = {
        target: ['cpu'],
        cpu: { threadNum: 2, threadAffinityMode: 1 }
      };

      // 3) 加载模型。
      this.model = await mindSporeLite.loadModelFromBuffer(modelBuffer, msContext);
      Logger.info(MindSporeFaceDetector.TAG, `model loaded in ${Date.now() - start}ms`);

      // 4) warmup：用全零张量跑一次，触发图编译与内存分配。
      await this.warmup();
    } catch (e) {
      this.model = null;
      this.modelData = null;
      Logger.error(MindSporeFaceDetector.TAG, 'load model failed', e as Error);
      throw e as Error;
    }
  }

  /** 用零张量预热模型。 */
  private async warmup(): Promise<void> {
    const model: mindSporeLite.Model | null = this.model;
    if (!model) {
      return;
    }
    const S: number = AppConstants.MODEL_INPUT_SIZE;
    const zeros: Float32Array = new Float32Array(3 * S * S);
    const inputs: mindSporeLite.MSTensor[] = model.getInputs();
    inputs[0].setData(zeros.buffer);
    const ws: number = Date.now();
    await model.predict(inputs);
    Logger.info(MindSporeFaceDetector.TAG, `warmup done in ${Date.now() - ws}ms`);
  }

  async detect(pixelMap: image.PixelMap): Promise<FaceDetection[]> {
    if (!this.model) {
      await this.load();
    }
    const model: mindSporeLite.Model | null = this.model;
    if (!model) {
      throw new Error('Face model not initialized');
    }

    // 1) 预处理(letterbox + 归一化 + CHW)。
    const pre: LetterboxResult = await Letterbox.preprocess(pixelMap);

    try {
      // 2) 写入输入张量并推理。
      const inputs: mindSporeLite.MSTensor[] = model.getInputs();
      inputs[0].setData(pre.buffer);
      const infStart: number = Date.now();
      const outputs: mindSporeLite.MSTensor[] = await model.predict(inputs);
      Logger.info(MindSporeFaceDetector.TAG, `inference ${Date.now() - infStart}ms`);

      // 3) 取输出并解码。
      const outBuffer: ArrayBuffer = outputs[0].getData();
      const outData: Float32Array = new Float32Array(outBuffer);
      const detections: FaceDetection[] = DetectionDecoder.decode(outData, pre.scale, pre.padX, pre.padY);
      Logger.info(MindSporeFaceDetector.TAG, `detected ${detections.length} face(s)`);
      return detections;
    } catch (e) {
      // 单次推理失败不阻断流程，返回空让用户手动添加(与其它检测器一致)。
      Logger.error(MindSporeFaceDetector.TAG, 'inference failed', e as Error);
      return [];
    }
  }

  async release(): Promise<void> {
    // MindSpore Lite 的 Model 由底层管理，置空引用以便回收；模型缓冲随后释放。
    this.model = null;
    this.loadingPromise = null;
    this.modelData = null;
  }
}
