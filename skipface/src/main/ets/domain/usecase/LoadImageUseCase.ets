/**
 * LoadImageUseCase.ets
 * 分层：domain / 用例
 *
 * 职责：把图片 uri 加载为 LoadedImage：解码降采样代理图 → 计算比例(原图留到导出按需解码)。
 * 依赖：PhotoRepository(解码)。
 */
import { PhotoRepository, ProxyDecodeResult } from '../../data/photo/PhotoRepository';
import { LoadedImage } from '../model/LoadedImage';
import { Result } from '../../common/base/Result';
import { AppConstants } from '../../common/constants/AppConstants';

export class LoadImageUseCase {
  private readonly photoRepo: PhotoRepository;

  constructor(photoRepo: PhotoRepository) {
    this.photoRepo = photoRepo;
  }

  /** @param uri 图片来源 uri(选择器/分享 want)。 */
  async execute(uri: string): Promise<Result<LoadedImage>> {
    return Result.runAsync<LoadedImage>(async (): Promise<LoadedImage> => {
      // 内存友好：仅解码降采样后的代理图常驻；全分辨率原图留到导出时按 uri 临时解码。
      const res: ProxyDecodeResult = await this.photoRepo.decodeProxy(uri, AppConstants.DISPLAY_MAX_SIDE);
      const aspectRatio: number = res.originalHeight > 0 ? res.originalWidth / res.originalHeight : 1;
      return new LoadedImage(
        uri,
        res.proxy,
        res.scaleToOriginal,
        aspectRatio,
        res.proxyWidth,
        res.proxyHeight
      );
    });
  }
}
