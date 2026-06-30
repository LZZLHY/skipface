/**
 * AppContainer.ets
 * 分层：common / 依赖注入容器
 *
 * 职责：在应用启动时集中装配单例(仓库、推理引擎、用例)，避免散落的全局单例，
 *       便于测试替换。采用"手写轻量 DI"：懒初始化 + 单例缓存。
 *
 * 用法：在 UIAbility.onWindowStageCreate 中调用 AppContainer.instance().init(context)。
 *       页面/ViewModel 通过 AppContainer.instance().xxx 获取依赖(未初始化访问会抛错)。
 *
 * 说明：依赖以"私有可空字段 + 受检 getter"暴露，避免 ArkTS 的 definite-assignment 警告，
 *       同时保证使用前已初始化。
 */
import { common } from '@kit.AbilityKit';
import { SettingsRepository } from '../../data/settings/SettingsRepository';
import { PhotoRepository } from '../../data/photo/PhotoRepository';
import { FaceDetector } from '../../capability/inference/FaceDetector';
import { CoreVisionFaceDetector } from '../../capability/inference/CoreVisionFaceDetector';
import { LoadImageUseCase } from '../../domain/usecase/LoadImageUseCase';
import { DetectFacesUseCase } from '../../domain/usecase/DetectFacesUseCase';
import { PlaceEmojiMasksUseCase } from '../../domain/usecase/PlaceEmojiMasksUseCase';
import { BuildBlurMasksUseCase } from '../../domain/usecase/BuildBlurMasksUseCase';
import { ExportImageUseCase } from '../../domain/usecase/ExportImageUseCase';
import { SaveImageUseCase } from '../../domain/usecase/SaveImageUseCase';
import { ShareImageUseCase } from '../../domain/usecase/ShareImageUseCase';
import { Logger } from '../utils/Logger';

export class AppContainer {
  private static singleton: AppContainer | null = null;

  private initialized: boolean = false;

  // 私有可空字段(init 后赋值)。
  private _settingsRepo: SettingsRepository | null = null;
  private _photoRepo: PhotoRepository | null = null;
  private _faceDetector: FaceDetector | null = null;
  private _loadImage: LoadImageUseCase | null = null;
  private _detectFaces: DetectFacesUseCase | null = null;
  private _placeEmoji: PlaceEmojiMasksUseCase | null = null;
  private _buildBlur: BuildBlurMasksUseCase | null = null;
  private _exportImage: ExportImageUseCase | null = null;
  private _saveImage: SaveImageUseCase | null = null;
  private _shareImage: ShareImageUseCase | null = null;

  private constructor() {}

  /** 获取全局容器单例。 */
  static instance(): AppContainer {
    if (!AppContainer.singleton) {
      AppContainer.singleton = new AppContainer();
    }
    return AppContainer.singleton;
  }

  /** 通用断言：未初始化时抛出明确错误。 */
  private require<T>(value: T | null, name: string): T {
    if (value === null) {
      throw new Error(`AppContainer not initialized: ${name}`);
    }
    return value;
  }

  get settingsRepo(): SettingsRepository {
    return this.require(this._settingsRepo, 'settingsRepo');
  }

  get photoRepo(): PhotoRepository {
    return this.require(this._photoRepo, 'photoRepo');
  }

  get faceDetector(): FaceDetector {
    return this.require(this._faceDetector, 'faceDetector');
  }

  get loadImage(): LoadImageUseCase {
    return this.require(this._loadImage, 'loadImage');
  }

  get detectFaces(): DetectFacesUseCase {
    return this.require(this._detectFaces, 'detectFaces');
  }

  get placeEmoji(): PlaceEmojiMasksUseCase {
    return this.require(this._placeEmoji, 'placeEmoji');
  }

  get buildBlur(): BuildBlurMasksUseCase {
    return this.require(this._buildBlur, 'buildBlur');
  }

  get exportImage(): ExportImageUseCase {
    return this.require(this._exportImage, 'exportImage');
  }

  get saveImage(): SaveImageUseCase {
    return this.require(this._saveImage, 'saveImage');
  }

  get shareImage(): ShareImageUseCase {
    return this.require(this._shareImage, 'shareImage');
  }

  /**
   * 初始化所有依赖。幂等。
   * @param context 应用/Ability 上下文(用于资源、相册等)。
   */
  async init(context: common.Context): Promise<void> {
    if (this.initialized) {
      return;
    }

    // 仓库
    const settings: SettingsRepository = new SettingsRepository();
    await settings.init(context);
    this._settingsRepo = settings;
    this._photoRepo = new PhotoRepository();

    // 能力(推理引擎)：默认使用 ONNX Runtime 直接加载 rawfile 的 YOLOv8-face 权重
    // (skipface_face.onnx)，端侧本地推理、开箱即用。若需改用系统视觉服务或 MindSpore Lite，
    // 改为 new CoreVisionFaceDetector() / new MindSporeFaceDetector(context) 即可。
    // 模型加载失败(如非 arm64 设备)时检测器内部优雅降级为空，应用仍可手动添加遮挡。
    // 能力(推理引擎)：默认使用系统 Core Vision Kit 人脸检测(CoreVisionFaceDetector)。
    // 系统服务为独立进程、随系统优化，不在应用进程内加载第三方原生模型，
    // 从根本上规避了 @ohos/onnxruntime NAPI 在 session.Run 抛出 C++ 异常(std::length_error)
    // 逸出 NAPI 边界导致整个进程 abort(SIGABRT) 的崩溃(多次进出编辑器后必现)。
    // 如需改回 YOLOv8/ONNX 或 MindSpore Lite，替换为 new OnnxFaceDetector(context) /
    // new MindSporeFaceDetector(context) 即可(三者共享同一 FaceDetector 抽象)。
    // 设备不支持系统人脸能力时检测器内部优雅降级为空，应用仍可手动添加遮挡。
    this._faceDetector = new CoreVisionFaceDetector();
    // 启动即异步预加载(初始化分析器)，使首张图片检测无需等待初始化耗时。
    this._faceDetector.load().catch((): void => {
      Logger.warn('AppContainer', 'detector preload failed (will retry on demand)');
    });

    // 用例
    this._loadImage = new LoadImageUseCase(this._photoRepo);
    this._detectFaces = new DetectFacesUseCase(this._faceDetector);
    this._placeEmoji = new PlaceEmojiMasksUseCase();
    this._buildBlur = new BuildBlurMasksUseCase();
    this._exportImage = new ExportImageUseCase();
    this._saveImage = new SaveImageUseCase(this._photoRepo);
    this._shareImage = new ShareImageUseCase(this._photoRepo);

    this.initialized = true;
  }

  isInitialized(): boolean {
    return this.initialized;
  }
}
