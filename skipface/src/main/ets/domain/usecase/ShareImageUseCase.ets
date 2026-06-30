/**
 * ShareImageUseCase.ets
 * 分层：domain / 用例
 *
 * 职责：把渲染后的 PixelMap 编码到缓存文件并调起系统分享。
 * 依赖：PhotoRepository。
 */
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { PhotoRepository } from '../../data/photo/PhotoRepository';
import { Result } from '../../common/base/Result';

export class ShareImageUseCase {
  private readonly photoRepo: PhotoRepository;

  constructor(photoRepo: PhotoRepository) {
    this.photoRepo = photoRepo;
  }

  async execute(context: common.UIAbilityContext, pixelMap: image.PixelMap): Promise<Result<void>> {
    return Result.runAsync<void>(async (): Promise<void> => {
      const fileUri: string = await this.photoRepo.packToCacheFile(context, pixelMap);
      await this.photoRepo.share(context, fileUri);
    });
  }
}
