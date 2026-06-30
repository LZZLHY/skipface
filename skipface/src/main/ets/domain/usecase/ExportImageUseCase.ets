/**
 * ExportImageUseCase.ets
 * 分层：domain / 用例
 *
 * 职责：在原图分辨率上重渲染最终图像(把代理图坐标系的遮挡放大后绘制)。
 * 依赖：ImageExporter(图像处理能力)。
 */
import { image } from '@kit.ImageKit';
import { ImageExporter, ExportRequest } from '../../capability/imaging/ImageExporter';
import { Result } from '../../common/base/Result';

export class ExportImageUseCase {
  /** @param req 导出请求(原图 + 遮挡 + 比例)。 */
  async execute(req: ExportRequest): Promise<Result<image.PixelMap>> {
    return Result.runAsync<image.PixelMap>((): Promise<image.PixelMap> => ImageExporter.export(req));
  }
}
