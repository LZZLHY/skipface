/**
 * PhotoRepository.ets
 * 分层：data / 数据层（相册与文件）
 *
 * 职责：图片的输入与输出：
 *   - pickImage：通过 PhotoViewPicker 选择图片(无需敏感权限)。
 *   - decode   ：把图片 uri 解码为 RGBA_8888 的 PixelMap。
 *   - packToCacheFile：把 PixelMap 编码为 PNG 写入应用缓存，返回 file:// uri(用于分享)。
 *   - createImageAsset / writeImageToAsset：配合 SaveButton 安全控件保存到系统相册(免静态权限)。
 *   - share     ：调起系统分享面板分享图片文件。
 *
 * 隐私：全程本地处理，不发起任何网络请求。
 * 异常：抛出的系统调用统一以 try/catch 包裹；失败向上抛出由用例的 Result 捕获。
 */
import { image } from '@kit.ImageKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { cameraPicker, camera } from '@kit.CameraKit';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../../common/utils/Logger';

export class PhotoRepository {
  private static readonly TAG: string = 'PhotoRepository';

  /** 调起图片选择器，返回所选图片 uri(取消则返回空)。 */
  async pickImage(): Promise<string> {
    try {
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      return result.photoUris.length > 0 ? result.photoUris[0] : '';
    } catch (e) {
      Logger.error(PhotoRepository.TAG, 'pickImage failed', e as Error);
      return '';
    }
  }

  /**
   * 调起系统相机拍摄一张照片，返回照片 uri(取消或失败返回空)。
   *
   * 说明：使用系统安全相机选择器 `cameraPicker`，由系统 UI 处理相机权限，
   *   应用无需静态声明 `ohos.permission.CAMERA`，符合"隐私优先"定位。
   * @param context UIAbility 上下文(拉起系统相机界面所需)。
   */
  async capturePhoto(context: common.Context): Promise<string> {
    try {
      const profile: cameraPicker.PickerProfile = {
        cameraPosition: camera.CameraPosition.CAMERA_POSITION_BACK
      };
      const result: cameraPicker.PickerResult = await cameraPicker.pick(
        context, [cameraPicker.PickerMediaType.PHOTO], profile
      );
      // resultCode === 0 表示拍摄成功；其余(如用户取消 -1)返回空。
      return result.resultCode === 0 && result.resultUri ? result.resultUri : '';
    } catch (e) {
      Logger.error(PhotoRepository.TAG, 'capturePhoto failed', e as Error);
      return '';
    }
  }

  /** 把图片 uri 解码为 RGBA_8888 PixelMap(供检测与渲染统一使用)。 */
  async decode(uri: string): Promise<image.PixelMap> {
    // 用文件 fd 创建图片源：PhotoPicker / 相册返回的 uri 直接以字符串传给 createImageSource
    // 在部分设备会失败(返回空)，经 fileIo 打开拿 fd 更稳妥、兼容性更好。
    const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    let source: image.ImageSource | undefined;
    try {
      source = image.createImageSource(file.fd);
      if (!source) {
        throw new Error('createImageSource 返回空(无法读取该图片)');
      }
      const options: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true
      };
      return await source.createPixelMap(options);
    } finally {
      // 防御：source 可能为空；且 finally 不应抛出以免覆盖 try 中的真实异常。
      if (source) {
        source.release();
      }
      fs.closeSync(file.fd);
    }
  }

  /**
   * 内存友好地解码"代理显示图"：在**解码阶段**用 desiredSize 直接降采样到目标尺寸，
   * 避免先解出全分辨率再读 RGBA、再复制、再缩放的多倍内存往返(大图会因此 OOM 崩溃)。
   * 编辑期只常驻该小图；全分辨率原图仅在导出时按 uri 临时解码。
   * @param uri     图片来源 uri。
   * @param maxSide 代理图最大边长(超过则按比例降采样)。
   * @returns 代理图 + 原图尺寸 + 代理→原图放大系数。
   */
  async decodeProxy(uri: string, maxSide: number): Promise<ProxyDecodeResult> {
    const file: fs.File = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    let source: image.ImageSource | undefined;
    try {
      source = image.createImageSource(file.fd);
      if (!source) {
        throw new Error('createImageSource 返回空(无法读取该图片)');
      }
      // 先取原图尺寸(不触发全分辨率解码)。
      const info: image.ImageInfo = await source.getImageInfo();
      const ow: number = info.size.width;
      const oh: number = info.size.height;
      const longest: number = Math.max(ow, oh);
      let dw: number = ow;
      let dh: number = oh;
      if (longest > maxSide && longest > 0) {
        const factor: number = maxSide / longest;
        dw = Math.max(1, Math.round(ow * factor));
        dh = Math.max(1, Math.round(oh * factor));
      }
      const options: image.DecodingOptions = {
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        editable: true,
        desiredSize: { width: dw, height: dh }
      };
      const proxy: image.PixelMap = await source.createPixelMap(options);
      // 兜底：个别解码器可能不采纳 desiredSize，返回全分辨率图。此时强制再缩放，
      // 确保编辑期"常驻"的代理图始终很小，避免大图常驻在多次进出后累积导致 OOM 崩溃。
      let proxyInfo: image.ImageInfo = await proxy.getImageInfo();
      let pw: number = proxyInfo.size.width;
      let ph: number = proxyInfo.size.height;
      const decodedLongest: number = Math.max(pw, ph);
      if (decodedLongest > maxSide && decodedLongest > 0) {
        const f: number = maxSide / decodedLongest;
        await proxy.scale(f, f);
        proxyInfo = await proxy.getImageInfo();
        pw = proxyInfo.size.width;
        ph = proxyInfo.size.height;
      }
      // 以"实际"代理尺寸反算放大系数：坐标换算(代理↔原图)始终精确。
      const proxyLongest: number = Math.max(pw, ph);
      const scaleToOriginal: number = proxyLongest > 0 ? longest / proxyLongest : 1;
      return {
        proxy,
        scaleToOriginal,
        originalWidth: ow,
        originalHeight: oh,
        proxyWidth: pw,
        proxyHeight: ph
      };
    } finally {
      if (source) {
        source.release();
      }
      fs.closeSync(file.fd);
    }
  }

  /** 将 PixelMap 编码为 PNG 字节。 */
  private async encodePng(pixelMap: image.PixelMap): Promise<ArrayBuffer> {
    const packer: image.ImagePacker = image.createImagePacker();
    try {
      const opts: image.PackingOption = { format: 'image/png', quality: 100 };
      return await packer.packToData(pixelMap, opts);
    } finally {
      packer.release();
    }
  }

  /**
   * 将 PixelMap 编码为 PNG 写入缓存目录，返回其 file:// uri。
   * @param context 提供 cacheDir。
   */
  async packToCacheFile(context: common.Context, pixelMap: image.PixelMap): Promise<string> {
    const data: ArrayBuffer = await this.encodePng(pixelMap);
    const dir: string = `${context.cacheDir}/share`;
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
    } catch (e) {
      Logger.warn(PhotoRepository.TAG, 'ensure share dir failed');
    }
    const path: string = `${dir}/skipface_${Date.now()}.png`;
    const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    try {
      fs.writeSync(file.fd, data);
    } finally {
      fs.closeSync(file.fd);
    }
    return fileUri.getUriFromPath(path);
  }

  /**
   * 在系统相册中创建一个空的图片资源，返回可写入的资源 uri。
   *
   * 说明：本方法需在 UI 侧 SaveButton 安全控件的点击授权窗口内"首先"被调用，
   *   系统据此授予一次性写入授权(免静态声明 WRITE_IMAGEVIDEO 权限)。
   *   创建得到的资源 uri 归本应用所有，后续写入(writeImageToAsset)不再需要授权。
   * @returns 新建相册资源的 uri。
   */
  async createImageAsset(context: common.Context): Promise<string> {
    const helper: photoAccessHelper.PhotoAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
    const assetUri: string = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png');
    Logger.info(PhotoRepository.TAG, 'created album asset');
    return assetUri;
  }

  /**
   * 把 PixelMap 编码为 PNG 并写入已创建的相册资源。
   * @param assetUri createImageAsset 返回的资源 uri。
   */
  async writeImageToAsset(assetUri: string, pixelMap: image.PixelMap): Promise<void> {
    const data: ArrayBuffer = await this.encodePng(pixelMap);
    const file: fs.File = fs.openSync(assetUri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
    try {
      fs.writeSync(file.fd, data);
    } finally {
      fs.closeSync(file.fd);
    }
    Logger.info(PhotoRepository.TAG, 'saved to album');
  }

  /**
   * 调起系统分享面板分享图片文件。
   * @param fileUriStr packToCacheFile 返回的 file:// uri。
   */
  async share(context: common.UIAbilityContext, fileUriStr: string): Promise<void> {
    const record: systemShare.SharedRecord = {
      utd: utd.UniformDataType.PNG,
      uri: fileUriStr
    };
    const data: systemShare.SharedData = new systemShare.SharedData(record);
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    });
  }
}

/** decodeProxy 返回值：代理图 + 原图尺寸 + 代理→原图放大系数。 */
export interface ProxyDecodeResult {
  proxy: image.PixelMap;
  scaleToOriginal: number;
  originalWidth: number;
  originalHeight: number;
  proxyWidth: number;
  proxyHeight: number;
}
