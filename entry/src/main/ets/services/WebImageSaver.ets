/**
 * WebImageSaver.ets
 * 网页图片保存至图库 / 链接复制（移植自 aira-browser WebImageContextActionService 的精简实现）
 */
import { http } from '@kit.NetworkKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

const MAX_BYTES: number = 30 * 1024 * 1024;

export class WebImageSaver {

  /** 长按图片 -> 保存到系统图库（走系统安全组件弹窗，无需敏感权限） */
  static async saveToGallery(context: common.UIAbilityContext, url: string,
    referer: string, cookie: string, userAgent: string): Promise<void> {
    try {
      const data: ArrayBuffer = await WebImageSaver.fetchImage(url, referer, cookie, userAgent);
      const ext: string = WebImageSaver.sniffExtension(data, url);
      const tempPath: string = await WebImageSaver.writeToCache(context, data, ext);

      const helper: photoAccessHelper.PhotoAccessHelper =
        photoAccessHelper.getPhotoAccessHelper(context);
      const assetUri: string = fileUri.getUriFromPath(tempPath);
      const photoAsset: photoAccessHelper.PhotoAsset = new photoAccessHelper.PhotoAsset(assetUri);
      const config: photoAccessHelper.PhotoCreationConfig = {
        title: 'TapTapWeb_' + Date.now(),
        fileNameExtension: ext,
        photoType: photoAccessHelper.PhotoType.IMAGE
      };
      const created: photoAccessHelper.PhotoAsset[] =
        await helper.showAssetsCreationDialog([photoAsset], [config]);
      if (created && created.length > 0) {
        const targetUri: string = created[0].uri;
        const targetFile = fileIo.openSync(targetUri, fileIo.OpenMode.READ_WRITE);
        fileIo.writeSync(targetFile.fd, new Uint8Array(data));
        fileIo.closeSync(targetFile);
        promptAction.showToast({ message: '已保存到图库' });
      } else {
        promptAction.showToast({ message: '已取消保存' });
      }
    } catch (err) {
      promptAction.showToast({ message: '保存失败：图片无法获取' });
    }
  }

  /** 复制文本（图片链接/视频链接） */
  static copyText(text: string, tip: string): void {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setData(data);
      promptAction.showToast({ message: tip });
    } catch (err) {
      promptAction.showToast({ message: '复制失败' });
    }
  }

  private static async fetchImage(url: string, referer: string,
    cookie: string, userAgent: string): Promise<ArrayBuffer> {
    const httpRequest = http.createHttp();
    try {
      const header: Record<string, string> = {};
      if (userAgent) {
        header['User-Agent'] = userAgent;
      }
      if (referer) {
        header['Referer'] = referer;
      }
      if (cookie) {
        header['Cookie'] = cookie;
      }
      const resp: http.HttpResponse = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: header,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 10000,
        readTimeout: 20000,
        maxLimit: MAX_BYTES / 1024
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error('HTTP ' + resp.responseCode);
      }
      return resp.result as ArrayBuffer;
    } finally {
      httpRequest.destroy();
    }
  }

  private static sniffExtension(data: ArrayBuffer, url: string): string {
    try {
      const bytes = new Uint8Array(data.slice(0, 16));
      if (bytes.length >= 4) {
        if (bytes[0] === 0xFF && bytes[1] === 0xD8) { return 'jpg'; }
        if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) { return 'png'; }
        if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) { return 'gif'; }
        if (bytes[0] === 0x52 && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42) { return 'webp'; }
      }
    } catch (err) { }
    const lower = url.toLowerCase();
    if (lower.indexOf('.png') > 0) { return 'png'; }
    if (lower.indexOf('.gif') > 0) { return 'gif'; }
    if (lower.indexOf('.webp') > 0) { return 'webp'; }
    if (lower.indexOf('.bmp') > 0) { return 'bmp'; }
    return 'jpg';
  }

  private static async writeToCache(context: common.UIAbilityContext,
    data: ArrayBuffer, ext: string): Promise<string> {
    const dir: string = context.cacheDir + '/web_images';
    try {
      fileIo.mkdirSync(dir, true);
    } catch (err) { }
    const path: string = dir + '/ttw_' + Date.now() + '.' + ext;
    const file = fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    fileIo.writeSync(file.fd, new Uint8Array(data));
    fileIo.closeSync(file);
    return path;
  }
}
