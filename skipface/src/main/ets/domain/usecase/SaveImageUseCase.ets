/**
 * SaveImageUseCase.ets
 * 分层：domain / 用例
 *
 * 职责：把渲染后的 PixelMap 保存到系统相册。拆分为两步以配合 SaveButton 安全控件：
 *   1) createAsset：在 SaveButton 授权窗口内"首先"创建相册资源(消费一次性授权)；
 *   2) write      ：把导出后的像素写入该资源(无需额外授权)。
 * 依赖：PhotoRepository。
 */
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { PhotoRepository } from '../../data/photo/PhotoRepository';
import { Result } from '../../common/base/Result';

export class SaveImageUseCase {
  private readonly photoRepo: PhotoRepository;

  constructor(photoRepo: PhotoRepository) {
    this.photoRepo = photoRepo;
  }

  /** 第一步：创建相册资源，返回可写入的资源 uri。须在 SaveButton 授权后立即调用。 */
  async createAsset(context: common.Context): Promise<Result<string>> {
    return Result.runAsync<string>((): Promise<string> => this.photoRepo.createImageAsset(context));
  }

  /** 第二步：把渲染结果写入已创建的相册资源。 */
  async write(assetUri: string, pixelMap: image.PixelMap): Promise<Result<void>> {
    return Result.runAsync<void>((): Promise<void> => this.photoRepo.writeImageToAsset(assetUri, pixelMap));
  }
}
