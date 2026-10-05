/**
 * WebImageSaver.ets
 * 网页图片保存至图库 / 链接复制（移植自 aira-browser WebImageContextActionService 的精简实现）
 */
import { http } from '@kit.NetworkKit';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

const MAX_BYTES: number = 30 * 1024 * 1024;

export class WebImageSaver {

  /** 长按图片 -> 保存到系统图库（走系统安全控件弹窗，无需敏感权限；失败回退系统保存选择器） */
  static async saveToGallery(context: common.UIAbilityContext, url: string,
    referer: string, cookie: string, userAgent: string): Promise<void> {
    try {
      const data: ArrayBuffer = await WebImageSaver.fetchImage(url, referer, cookie, userAgent);
      if (!data || data.byteLength === 0) {
        promptAction.showToast({ message: '保存失败：图片内容为空' });
        return;
      }
      const ext: string = WebImageSaver.sniffExtension(data, url);
      const tempPath: string = await WebImageSaver.writeToCache(context, data, ext);

      try {
        // 首选：安全控件创建对话框（免权限，写完即入图库）
        const helper: photoAccessHelper.PhotoAccessHelper =
          photoAccessHelper.getPhotoAccessHelper(context);
        const assetUri: string = fileUri.getUriFromPath(tempPath);
        const config: photoAccessHelper.PhotoCreationConfig = {
          title: 'TapTapWeb_' + Date.now(),
          fileNameExtension: ext,
          photoType: photoAccessHelper.PhotoType.IMAGE
        };
        const created: string[] =
          await helper.showAssetsCreationDialog([assetUri], [config]);
        if (created && created.length > 0) {
          const targetUri: string = created[0];
          const targetFile = fileIo.openSync(targetUri, fileIo.OpenMode.READ_WRITE);
          fileIo.writeSync(targetFile.fd, new Uint8Array(data));
          fileIo.closeSync(targetFile);
          promptAction.showToast({ message: '已保存到图库' });
        } else {
          promptAction.showToast({ message: '已取消保存' });
        }
      } catch (dialogErr) {
        // 回退：系统"保存图片"选择器（用户选位置后写入，同样免权限）
        try {
          const saveOptions = new picker.PhotoSaveOptions();
          saveOptions.newFileNames = ['TapTapWeb_' + Date.now() + '.' + ext];
          const viewPicker = new picker.PhotoViewPicker();
          const uris: Array<string> = await viewPicker.save(saveOptions);
          if (uris && uris.length > 0) {
            const targetFile = fileIo.openSync(uris[0], fileIo.OpenMode.READ_WRITE);
            fileIo.writeSync(targetFile.fd, new Uint8Array(data));
            fileIo.closeSync(targetFile);
            promptAction.showToast({ message: '已保存' });
          } else {
            promptAction.showToast({ message: '已取消保存' });
          }
        } catch (pickErr) {
          const pe = pickErr as BusinessError;
          const msg: string = (pe && pe.message) ? pe.message : '未知错误';
          promptAction.showToast({ message: '保存失败：' + msg });
        }
      }
    } catch (err) {
      const be = err as BusinessError;
      const msg: string = (be && be.message) ? be.message : '图片无法获取';
      promptAction.showToast({ message: '保存失败：' + msg });
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
