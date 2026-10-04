import { webview } from '@kit.ArkWeb';
import { promptAction, window, display, prompt } from '@kit.ArkUI';
import { common, Want, OpenLinkOptions, ConfigurationConstant } from '@kit.AbilityKit';
import util from '@ohos.util';
import {
  saveHomeUrl,
  getHomeUrl,
  saveUserAgent,
  getUserAgent,
  saveLSRefresh,
  getLSRefresh,
  saveIshidebar,
  getIshidebar,
  getIshidestatus,
  saveIshidestatus,
  getUserAgentType,
  saveUserAgentType,
  getIsfull,
  saveIsfull,
  getSlidenum,
  saveSlidenum,
  saveWebDarkMode,
  getWebDarkMode,
  saveFakeAppUa,
  getFakeAppUa
} from '../model/StorageService';
import { DownloadConfirmDialog } from '../component/DownloadConfirmDialog'
import { IAbstractDownloadHandler } from '../delegate/IWebDownloadFile'
import { WebDownloadFileHelper } from '../delegate/WebDownloadFileImpl'
import { EmitterUtil } from '../utiles/EmitterUtil'
import { WEB_CHROME_SCRIPT } from '../utiles/WebChromeScript'
import { WebImageSaver } from '../services/WebImageSaver'
import { http } from '@kit.NetworkKit';
import { fileIo as fs, ReadOptions, WriteOptions } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError, systemDateTime } from '@kit.BasicServicesKit';
import { preferences } from '@kit.ArkData';
import { buffer } from '@kit.ArkTS';

enum ScreenOrientation {
  PORTRAIT = display.Orientation.PORTRAIT,
  LANDSCAPE = display.Orientation.LANDSCAPE,
  REVERSE_PORTRAIT = display.Orientation.PORTRAIT_INVERTED,
  REVERSE_LANDSCAPE = display.Orientation.LANDSCAPE_INVERTED
}

let context_index = getContext(this) as common.UIAbilityContext;
let resourceDir = context_index.resourceDir

//console.log("Dir"+resourceDir)

const TAG = 'web-savePic';
const context = getContext(this) as common.UIAbilityContext;
/**
 * 复制本地文件到应用沙箱,并返回保存后的沙箱中的文件路径
 */
function copyLocalPicFilesDir(rawfilePath: string, newFileName: string): string {
  let srcFileDescriptor = context.resourceManager.getRawFdSync(rawfilePath); //这里填rawfile文件夹下的文件名（包括后缀）
  let dstPath = context.filesDir + "/" + newFileName;
  let dest: fs.File = fs.openSync(dstPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE)
  let bufsize = 4096
  let buf = new ArrayBuffer(bufsize)
  let off = 0, len = 0, readedLen = 0
  while (len = fs.readSync(srcFileDescriptor.fd, buf, { offset: srcFileDescriptor.offset + off, length: bufsize })) {
    readedLen += len
    fs.writeSync(dest.fd, buf, { offset: off, length: len })
    off = off + len
    if ((srcFileDescriptor.length - readedLen) < bufsize) {
      bufsize = srcFileDescriptor.length - readedLen
    }
  }
  fs.close(dest.fd)

  return dest.path;
}

async function copyUrlPicToFilesDir(picUrl: string, newFileName: string): Promise<string> {
  let uri = '';
  //读取网络图片并保存到沙箱路径下
  let httpRequest = http.createHttp();
  let data: http.HttpResponse = await (httpRequest.request(picUrl) as Promise<http.HttpResponse>);
  if (data?.responseCode == http.ResponseCode.OK) {
    let dstPath = context.filesDir + "/" + newFileName;
    let dest: fs.File = fs.openSync(dstPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE)
    let writeLen: number = fs.writeSync(dest.fd, data.result as ArrayBuffer);
    uri = dest.path;
  }
  return uri;
}



@Entry
@Component
struct Index {
  private isRefreshing: boolean = false;
  private contextmenu_result: WebContextMenuResult | undefined = undefined;
  @State controller: webview.WebviewController = new webview.WebviewController();
  @State webDownloadFile: IAbstractDownloadHandler = new WebDownloadFileHelper()
  downloadWebLoading: CustomDialogController = new CustomDialogController({
    //Web页面加载的弹窗控制器
    builder: DownloadConfirmDialog(),
    customStyle: true,
    alignment: DialogAlignment.Bottom,
    autoCancel: false,
    isModal: false
  })

  saveButtonOptions: SaveButtonOptions = {
    icon: SaveIconStyle.FULL_FILLED,
    text: SaveDescription.SAVE_IMAGE,
    buttonType: ButtonType.Capsule
  } // 设置安全控件按钮属性
  private result: WebContextMenuResult | undefined = undefined;
  @State linkUrl: string = '';
  @State imgUrl: string = '';
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State showMenu: boolean = false;
  @State pic_w:number|undefined = 0;
  @State pic_h:number|undefined = 0;
  @State pic_dl_show:Visibility = Visibility.Hidden;
  private shouldClearCache: boolean = false;
  @Builder
  //构建自定义菜单及触发功能接口
  MenuBuilder() {
    Column() {
      Row()
        .height(10)
      Row(){
        Text('是否保存至图库')
          .fontColor($r('app.color.dialog_text'))
          .fontSize(18)
      }
      Row(){
        //Text(this.imgUrl)
      }
        .height(10)
      Row(){
        Image(this.imgUrl)
          .onComplete((event) => {
            this.pic_w = event?.width;
            this.pic_h = event?.height;
            this.pic_dl_show = Visibility.Visible;
            })
          .onError(()=>{
            this.showMenu=false;
            this.pic_dl_show = Visibility.Hidden;
          })
          .width('80%')
          .backgroundColor($r('app.color.panel_bg'))
          .borderRadius(15)
          .objectFit(ImageFit.ScaleDown)
          .constraintSize({maxHeight: '50%',maxWidth:'80%'})
      }
      //.constraintSize({maxHeight: '50%',maxWidth:'80%'})

      Row() {
        Button("取消").onClick((event: ClickEvent) => {
          this.showMenu = false;
          this.pic_dl_show = Visibility.Hidden;
        })
          .height(32)
          .backgroundColor($r('app.color.ctx_menu_bg'))
        Text()
          .width(10)
        SaveButton(this.saveButtonOptions) // 创建安全控件按钮。
          .onClick(async (event, result: SaveButtonOnClickResult) => {
            if (result == SaveButtonOnClickResult.SUCCESS) {
              try {
                let context = getContext();
                let phAccessHelper = photoAccessHelper.getPhotoAccessHelper(context);
                let uri = '';
                //复制图片到应用沙箱目录下，并获取uri
                if (this.imgUrl?.includes('rawfile')) {
                  let rawFileName: string = this.imgUrl.substring(this.imgUrl.lastIndexOf('/') + 1);
                  console.info(TAG, `rawfileName ${rawFileName}`)
                  uri = copyLocalPicFilesDir(rawFileName, 'copyFile.png');
                } else if (this.imgUrl?.includes('http') || this.imgUrl?.includes('https')) { // 针对http|https 协议的网络图片
                  uri = await copyUrlPicToFilesDir(this.imgUrl, `onlinePic_${systemDateTime.getTime()}.png`)
                }
                let assetChangeRequest: photoAccessHelper.MediaAssetChangeRequest = photoAccessHelper.MediaAssetChangeRequest.createImageAssetRequest(context, uri);
                await phAccessHelper.applyChanges(assetChangeRequest);
                console.info('createAsset successfully, uri: ' + assetChangeRequest.getAsset().uri);
                this.showMenu = false;
              } catch (err) {
                console.error(`create asset failed with error: ${err.code}, ${err.message}`);
                //this.showMenu = false;
              }
            } else {
              console.error('SaveButtonOnClickResult create asset failed');
              //this.showMenu = false;
            }
            //this.showMenu = false;
          })
      }
      .height(32)
      .margin({ top: 20, bottom: 20 })
      .justifyContent(FlexAlign.Center)
    }
    .width('80%')
    .backgroundColor($r('app.color.ctx_menu_bg'))
    .borderRadius(10)
    .visibility(this.pic_dl_show)
  }



  async saveBase64Image(base64Str:string) {

    try {
      const context = getContext(this);
      let helper = photoAccessHelper.getPhotoAccessHelper(context);
      let uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png')
      let imageStr = base64Str.split(',')[1];
      //打开文件
      let file = fs.openSync(uri, fs.OpenMode.READ_WRITE);
      //base64字符串转成buffer
      const decodeBuffer = buffer.from(imageStr, 'base64').buffer;
      //写入文件
      fs.writeSync(file.fd, decodeBuffer);
      //关闭文件
      fs.closeSync(file);

    } catch (e) {
      console.error(e);
    }
  }

  @State refreshing: boolean = false
  @State list: number[] = Array(20).fill(Date.now())
  @State is_home: boolean = false;
  @State showDialog: boolean = false;
  //home_url = "http://nas2.smder.com:3002"
  @State home_url: string = ''
  @State saved_home_url: string = 'https://www.taptap.cn/';
  @State c_pg_ua: string = '';
  @State c_ua_temp: string = '';
  @State ua_type: string = 'Mobile';
  @State fakeAppUa: string = 'true'; // 伪装 TapTap 客户端 UA
  @State userAgent: string = '';
  @State ua_device: string = '';
  @State showTopRow: boolean = false;
  @State showRefreshRow: boolean = true;
  @State showButtonRow: boolean = true;
  @State refreshTimerId: number | null = null;
  @State showSetting: boolean = false;
  @State isLandscape: boolean = false;
  @State isLSRefresh: string = 'flase'; //是否横屏不能刷新
  @State isdrag: number = 1
  @State isHidebar: string = 'false';
  @State isHidestatus: string = 'false';
  @State isFull: string = 'true';
  @State slide_num: number = 0.3;
  @State webDark: string = 'auto'; // 'auto'=跟随系统深浅色, 'dark'=强制深色
  // 沉浸式：状态栏高度留白(px->vp)，供下拉顶栏避开状态栏
  @State safeTopVp: number = 0;
  // 全屏避让填充色：状态栏区域与页面顶部采样色一致，避免色差断层
  @State topFillColor: string = '';
  private lastTopBg: string = '';
  private lastBottomBg: string = '';
  // 长按上下文菜单（图片/视频）
  @State ctxVisible: boolean = false;
  @State ctxX: number = 0;
  @State ctxY: number = 0;
  @State ctxItems: string[] = [];
  private ctxUrl: string = '';
  // 发布器页已强制桌面 UA（离开发布器 URL 时在 onLoadIntercept 恢复）
  private uaForcedDesktop: boolean = false;
  // 纯 Web 体验页已临时摘除 TapTap 伪装 UA（离开发时在 onLoadIntercept 恢复）
  private uaForcedWeb: boolean = false;




  async setSystemFull(is_full: string, is_hidestatus: string, is_hidebar: string) {
    let windowClass = await window.getLastWindow(context_index)
    if (is_full == 'true') {
      if (is_hidestatus == 'true') {
        if (is_hidebar == 'true') {
          await windowClass.setWindowLayoutFullScreen(true)
          await windowClass.setSpecificSystemBarEnabled('status', true, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', true, true);

        } else {
          await windowClass.setWindowLayoutFullScreen(true)
          await windowClass.setSpecificSystemBarEnabled('status', true, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', false, true);

        }
      } else {
        if (is_hidebar == 'true') {
          await windowClass.setWindowLayoutFullScreen(true)
          await windowClass.setSpecificSystemBarEnabled('status', false, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', true, true);

        } else {
          await windowClass.setWindowLayoutFullScreen(true)
          await windowClass.setSpecificSystemBarEnabled('status', false, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', false, true);

        }
      }
    } else {
      if (is_hidestatus == 'true') {
        if (is_hidebar == 'true') {
          // 小白条开启：必须全屏布局。非全屏布局下系统会把导航栏画成默认黑，
          // navigationBarColor 被忽略；全屏布局下窗口延伸到小白条下方，采样色可正常上屏
          await windowClass.setWindowLayoutFullScreen(true)
          await windowClass.setSpecificSystemBarEnabled('status', true, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', true, true);
        } else {
          await windowClass.setWindowLayoutFullScreen(false)
          await windowClass.setSpecificSystemBarEnabled('status', true, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', false, true);

        }
      } else {
        if (is_hidebar == 'true') {
          await windowClass.setWindowLayoutFullScreen(true)
          await windowClass.setSpecificSystemBarEnabled('status', false, true);

          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', true, true);

        } else {
          await windowClass.setWindowLayoutFullScreen(false)
          await windowClass.setSpecificSystemBarEnabled('status', false, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', false, true);

        }
      }
    }
    // 系统栏样式：非全屏时状态栏/小白条背景取页面采样色；全屏同理
    await this.updateSystemBarStyle();
    // navigationIndicator 异步生效，会把导航栏颜色重置回系统默认黑：延时重设
    setTimeout(() => {
      this.updateSystemBarStyle(this.lastTopBg, this.lastBottomBg);
    }, 350);
    // 计算状态栏高度留白（下拉顶栏避开状态栏）
    try {
      const area = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.safeTopVp = px2vp(area.topRect.top);
    } catch (err) {
      this.safeTopVp = 0;
    }
  }

  async aboutToAppear() {
    // 系统深浅色切换：强制重设系统栏（深色：顶栏#1B1C21/底栏#161920）
    EmitterUtil.on<number>('ttw_color_mode_changed', (event) => {
      // 系统深浅色切换：用最近采样色强制重设系统栏
      this.applyImmersiveTheme(this.lastTopBg, this.lastBottomBg, true);
    });
    // 网页缓存管理：记录最后使用时间；超过 7 天未使用，启动时自动清除缓存
    preferences.getPreferences(context_index, 'ttw_web_cache').then((pref) => {
      const now: number = systemDateTime.getTime();
      pref.get('cache_updated_at', 0).then((v) => {
        const last: number = typeof v === 'number' ? v : 0;
        if (last > 0 && now - last > 7 * 24 * 60 * 60 * 1000) {
          this.shouldClearCache = true;
        }
        pref.put('cache_updated_at', now).then(() => {
          pref.flush();
        });
      });
    }).catch(() => {
    });
    EmitterUtil.on<number>('affffa', (event) => {
      if (event?.data === 1) {
        this.downloadWebLoading.open()
      } else {
        this.downloadWebLoading.close()
      }
    })
    this.isLSRefresh = await getLSRefresh() || this.isLSRefresh;
    this.c_pg_ua = await getUserAgent() || this.c_pg_ua;
    this.c_ua_temp = await getUserAgent() || this.c_pg_ua;
    this.saved_home_url = await getHomeUrl() || this.saved_home_url;
    this.isHidebar = (await getIshidebar() || this.isHidebar);
    this.isHidestatus = (await getIshidestatus() || this.isHidestatus);
    this.ua_type = (await getUserAgentType() || this.ua_type);
    this.fakeAppUa = (await getFakeAppUa() || this.fakeAppUa);
    this.isFull = (await getIsfull() || this.isFull);
    this.slide_num = (await getSlidenum() || this.slide_num);
    this.webDark = (await getWebDarkMode() || this.webDark);
    // 开启预连接需要先使用上述方法预加载WebView内核。
    //webview.WebviewController.initializeWebEngine();
    // 启动预连接，连接地址为即将打开的网址。
    //webview.WebviewController.prepareForPageLoad(this.saved_home_url, true, 2);

    setTimeout(() => {
      this.backToHome();
      this.setSystemFull(this.isFull, this.isHidestatus, this.isHidebar);
    }, 50);
  }

  aboutToDisappear(): void {
    EmitterUtil.off<number>('affffa', (event) => {

    })
    EmitterUtil.unSubscribe('ttw_color_mode_changed');
  }

  @Builder
  content() {
    Stack() {
      Column() {
        Row() {
          TextInput({
            placeholder: '请输入有效的URL地址',
            text: this.saved_home_url
          })
            .height(32)
            .width("80%")
            .onChange((value) => {
              this.home_url = value;
            })

          Button('保存')
            .height(32)
            .width("15%")
            .type(ButtonType.Capsule)
            .backgroundColor(Color.Blue)
            .onClick(() => {
              if (this.home_url) {
                saveHomeUrl(this.home_url);
                this.saved_home_url = this.home_url
                this.backToHome();
              }
              this.showTopRow = false
              this.showRefreshRow = true
              this.showButtonRow = true
              //this.isRefreshing = true;
              //this.refreshing = true;
              this.onRefreshing();
            })
        }
        .visibility(this.showTopRow ? Visibility.Visible : Visibility.None)
        .height(40)
        .width("100%")
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.SpaceAround)

        Row() {
          LoadingProgress()
            .height(32)
          Text('正在刷新...')
              .fontColor($r('app.color.dialog_text'))
            .fontSize(16)
            .margin({ left: 20 })
        }
        .visibility(this.showRefreshRow ? Visibility.Visible : Visibility.None)
        .alignItems(VerticalAlign.Center)

        Row() {
          Button({ type: ButtonType.Circle }) {
            Image($r('app.media.settings'))
              .width(20)
              .height(20)
          }
          .onClick(() => {
            //this.showTopRow = false
            //this.showTopRow = true
            //this.showRefreshRow = false
            //this.showButtonRow = false
            //this.cancelRefresh()
            this.showSetting = true
          })
          .height(32)
          .width(32)

          //.type(ButtonType.Normal)
          Button("清除缓存")
            .onClick(() => {
              this.controller.removeCache(true)
            })
            .height(32)
            .width("25%")
          //.type(ButtonType.Normal)
          Button("返回首页")
            .onClick(() => {
              this.is_home = true
              this.backToHome()
              setTimeout(() => {
                this.is_home = false
              }, 1000);
            })
            .height(32)
            .width("60%")
          //.type(ButtonType.Normal)
          // 条件渲染弹窗

        }
        .visibility(this.showButtonRow ? Visibility.Visible : Visibility.None)
        .padding({ top: 5, bottom: 5 })
        .height(40)
        .width("100%")
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.panel_bg'))
        .justifyContent(FlexAlign.SpaceAround)
      }
      .padding({ top: this.safeTopVp })
    }

  }

  build() {
    Stack() {
      Refresh({ refreshing: $$this.refreshing, builder: this.content() }) {
        NavDestination() {
          Column() {
            Web({ src: this.saved_home_url, controller: this.controller })
              .onControllerAttached(() => {
                this.controller.setNetworkAvailable(true);
                this.webDownloadFile.setDownloadDelegate(this.controller);
                if (this.shouldClearCache) {
                  this.shouldClearCache = false;
                  try {
                    this.controller.removeCache(true);
                  } catch (err) {
                  }
                }
                console.info("onControllerAttached");
                try {
                  this.change_userAgent()
                } catch (error) {
                  console.error(`ErrorCode: ${(error as BusinessError).code},  Message: ${(error as BusinessError).message}`);
                }
              })
              .onContextMenuShow((event) => {
                  this.result = event.result
                  this.linkUrl = event.param.getLinkUrl();
                  this.imgUrl = event.param.getSourceUrl();
                  let hitValue = this.controller.getHitTestValue()
                  let img64 = hitValue.extra
                if(this.imgUrl==''&&img64!=''){
                  this.imgUrl = img64
                }
                //this.linkUrl = this.imgUrl
                let mediaType = event.param.getMediaType()
                if (mediaType === ContextMenuMediaType.Image) {
                  if(this.imgUrl.startsWith("data:image")) {
                    //this.saveBase64Image(img64);
                  }else{
                    if(this.imgUrl != '') {
                      this.showMenu = true;
                      this.pic_dl_show = Visibility.Hidden;
                    }
                  }
                }

                //this.offsetX = 0;
                //this.offsetY = Math.max(px2vp(event?.param.y() ?? 0) - 0, 0);
                return true;
              })
              .bindPopup(this.showMenu,
                {
                  builder: this.MenuBuilder(),
                  enableArrow: false,
                  placement: Placement.LeftTop,
                  offset: { x: this.offsetX, y: this.offsetY },
                  mask: false,
                  onStateChange: (e) => {
                    if (!e.isVisible) {
                      this.showMenu = false;
                    }
                  }
                })
              //.cacheMode(CacheMode.Online)
              .domStorageAccess(true)
              //.multiWindowAccess(true)
              .javaScriptAccess(true)
              .geolocationAccess(true)
              .imageAccess(true)
              .onlineImageAccess(true)
              .fileAccess(true)
              .mediaPlayGestureAccess(true)
              .mixedMode(MixedMode.Compatible)
              .darkMode(this.webDark === 'dark' ? WebDarkMode.On : WebDarkMode.Auto)
              .forceDarkAccess(this.webDark === 'dark')
              .backgroundColor($r('app.color.panel_bg'))
              .javaScriptOnDocumentStart([{ script: WEB_CHROME_SCRIPT, scriptRules: ['*'] }])
              .onConsole((event) => {
                // 沉浸式取色桥：页面探针经 console 上报主题背景色
                if (event && event.message) {
                  const msg: string = event.message.getMessage() || '';
                  if (msg.indexOf('__TTW_CHROME__') === 0) {
                    try {
                      const payload = JSON.parse(msg.substring('__TTW_CHROME__'.length)) as Record<string, string>;
                      this.applyImmersiveTheme(payload.bg || '', payload.bbg || '');
                    } catch (err) {
                    }
                  }
                }
                return false;
              })
              .onContextMenuShow((event) => {
                return this.handleWebContextMenu(event);
              })
              .onLoadIntercept((event) => {
                // 拦截非网页协议的跳转，交给系统/外部应用打开（如 taptap:// 等应用深链）
                if (event && event.data) {
                  const url: string = event.data.getRequestUrl() || '';
                  const scheme: string = url.split(':')[0]?.toLowerCase() || '';
                  const webSchemes: string[] = ['http', 'https', 'file', 'about', 'data', 'blob', 'javascript'];
                  if (scheme !== '' && !webSchemes.includes(scheme)) {
                    this.openExternalApp(url);
                    return true; // 拦截，不让 WebView 自己加载
                  }
                  // 发布器页移动网页端未适配（页面自述面向电脑端）：进入时自动改用桌面 UA，离开时恢复
                  // 仅处理主文档导航，避免页面内 XHR/子资源请求触发 UA 反复切换
                  if ((scheme === 'http' || scheme === 'https') && event.data.isMainFrame()) {
                    const isPub = this.isPublisherUrl(url);
                    const isWebOnly = this.isWebOnlyUrl(url);
                    if (this.ua_type === 'Mobile') {
                      // 纯 Web 体验页（poster 活动页/网页云玩）：临时摘除 TapTap 伪装标识，避免页面走客户端专属流
                      if (this.fakeAppUa === 'true') {
                        if (isWebOnly && !this.uaForcedWeb) {
                          this.uaForcedWeb = true;
                          this.controller.setCustomUserAgent(this.getuseragentbytype('Mobile'));
                          this.controller.loadUrl(url);
                          return true;
                        }
                        if (!isWebOnly && this.uaForcedWeb) {
                          this.uaForcedWeb = false;
                          this.change_userAgent();
                          this.controller.loadUrl(url);
                          return true;
                        }
                      }
                      if (isPub && !this.uaForcedDesktop) {
                        this.uaForcedDesktop = true;
                        this.controller.setCustomUserAgent(this.getuseragentbytype('PC'));
                        this.controller.loadUrl(url);
                        return true;
                      }
                      if (!isPub && this.uaForcedDesktop) {
                        this.uaForcedDesktop = false;
                        this.change_userAgent();
                        this.controller.loadUrl(url);
                        return true;
                      }
                    }
                  }
                }
                return false;
              })

          }
          .width("100%")
          .height("100%")
          // 状态栏避让：全屏布局下 Web 从状态栏下方起排，避让区用页面顶部采样色填充
          .padding({ top: this.safeTopVp })
          .backgroundColor(this.topFillColor === '' ? $r('app.color.panel_bg') : this.topFillColor)

        }

      }
      .pullDownRatio(this.slide_num * this.isdrag)
      .backgroundColor($r('app.color.panel_bg'))
      .onRefreshing(() => this.onRefreshing())
      .onSizeChange(() => {
        window.getLastWindow(this.getUIContext().getHostContext(), (err, win) => {
          let cutOutInfo = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM_GESTURE)
          //console.log(JSON.stringify(cutOutInfo))
          if (window.Orientation.AUTO_ROTATION) {
            let rotation: number =
              display.getDefaultDisplaySync().orientation // Get current screen orientation enum value
            //console.log('' + rotation);
            if (this.isLSRefresh == 'true') {
              if (rotation == 0) {
                this.isLandscape = false;
                this.isdrag = 1;
                //console.log("CutOutInfo Portrait data: " + JSON.stringify(cutOutInfo));
              } else if (rotation == 1) {
                this.isLandscape = true;
                this.isdrag = 0;
                //console.log("CutOutInfo Landscape data: " + JSON.stringify(cutOutInfo));
              } else if (rotation == 2) {
                this.isLandscape = false;
                this.isdrag = 1;
                //console.log("CutOutInfo Reverse portrait data: " + JSON.stringify(cutOutInfo));
              } else {
                this.isLandscape = true;
                this.isdrag = 0;
                //console.log("CutOutInfo Reverse landscape data: " + JSON.stringify(cutOutInfo));
              }
            }
          }
        })
      })
      .width('100%')
      .height('100%')

      //弹窗
      Column() {
        Column() {
          Row() {
            Text("首页")
              .fontColor($r('app.color.dialog_text'))
              .width("12%")
              .height(32)
            TextInput({
              placeholder: '请输入有效的URL地址',
              text: this.saved_home_url
            })
              .height(32)
              .width("70%")
              .padding({
                top: '4vp',
                right: '12vp',
                bottom: '4vp',
                left: '12vp'

              })
              .onChange((value) => {
                this.home_url = value;
              })
            Text()
              .width(7)

            Button('保存')
              .height(32)
              .width("18%")
              .type(ButtonType.Capsule)
              //.backgroundColor(Color.Blue)
              .onClick(() => {
                if (this.home_url) {
                  saveHomeUrl(this.home_url);
                  this.saved_home_url = this.home_url;
                  this.backToHome();
                }
              })
          }

          Row()
            .height(10)

          Row() {
            Text("UA")
              .fontColor($r('app.color.dialog_text'))
              .width('12%')
            Text()
              .width(15)
            Radio({ value: 'Mobile', group: 'ua_type_group' })
              .checked(this.ua_type === 'Mobile') // 判断是否选中
              .onChange((isChecked) => {
                if (isChecked) {
                  this.ua_type = 'Mobile'; // 更新选中值
                  saveUserAgentType('Mobile');
                  this.change_userAgent();
                  this.refreshWeb();
                }
              })
              .height(20)
            Text("手机")
              .fontColor($r('app.color.dialog_text'))
              .onClick(() => {
                if (this.ua_type == 'custom') {
                  this.c_ua_temp = this.getuseragentbytype('Mobile');
                }
              })
            Text()
              .width(7)
            Radio({ value: 'PC', group: 'ua_type_group' })
              .checked(this.ua_type === 'PC') // 判断是否选中
              .onChange((isChecked) => {
                if (isChecked) {
                  this.ua_type = 'PC'; // 更新选中值
                  saveUserAgentType('PC');
                  this.change_userAgent();
                  this.refreshWeb();
                }
              })
              .height(20)
            Text("电脑")
              .fontColor($r('app.color.dialog_text'))
              .onClick(() => {
                if (this.ua_type == 'custom') {
                  this.c_ua_temp = this.getuseragentbytype('PC');
                }
              })
            Text()
              .width(7)

            Radio({ value: 'custom', group: 'ua_type_group' })
              .checked(this.ua_type === 'custom') // 判断是否选中
              .onChange((isChecked) => {
                if (isChecked) {
                  this.ua_type = 'custom'; // 更新选中值
                  saveUserAgentType('custom');
                  this.change_userAgent();
                  this.refreshWeb();
                }
              })
              .height(20)
            Text("自定义")
              .fontColor($r('app.color.dialog_text'))
              .onClick(() => {
                if (this.ua_type == 'custom') {
                  this.c_ua_temp = this.getuseragentbytype('custom');
                }
              })
          }
          .justifyContent(FlexAlign.SpaceAround)
          .width('100%')

          Row() {
            TextArea({
              text: this.c_ua_temp,
              //text: this.c_pg_ua,
              placeholder: '请输入UA(可不填)，确认才保存.点击上方[手机][电脑][自定义]文字可以将其UA复制到此处。'
            })
            //.maxLines(5)
              .height(190)
              .textAlign(TextAlign.Start)
              .width("82%")
              .onChange((value) => {
                this.c_ua_temp = value;
              })

            Text()
              .width(7)

            Button('保存')
              .height(32)
              .width("18%")
              .type(ButtonType.Capsule)
              //.backgroundColor(Color.Blue)
              .onClick(() => {
                if (this.c_ua_temp) {
                  this.c_pg_ua = this.c_ua_temp;
                  saveUserAgent(this.c_pg_ua);
                  this.change_userAgent()
                  this.refreshWeb();
                }
              })
          }
          .visibility(this.ua_type == 'custom' ? Visibility.Visible : Visibility.None)

          //.alignItems(VerticalAlign.Top)
          Row()
            .height(10)

          Row() {
            Text("横屏禁止刷新")
              .fontColor($r('app.color.dialog_text'))
              .width("35%")
              .height(32)
            Text()
              .width('50%')
            Toggle({
              type: ToggleType.Switch,
              isOn: this.get_isLSRefresh()
            })
              .width('15%')
              .height(25)
              //.selectedColor(Color.Blue)
              .onChange((isOn: boolean) => {
                if (isOn) {
                  this.isLSRefresh = 'true';
                  saveLSRefresh(this.isLSRefresh);
                  if (this.isLandscape == true) {
                    this.isdrag = 1;
                  } else {
                    this.isdrag = 0;
                  }
                } else {
                  this.isLSRefresh = 'false';
                  saveLSRefresh(this.isLSRefresh);
                  this.isdrag = 1;
                }

              })

          }
          .justifyContent(FlexAlign.SpaceAround)
          .width('100%')

          Row() {
            Text("全屏模式")
              .fontColor($r('app.color.dialog_text'))
              .width("35%")
              .height(32)
            Text()
              .width('50%')
            Toggle({
              type: ToggleType.Switch,
              isOn: this.get_isfull()
            })
              .width('15%')
              .height(25)
              //.selectedColor(Color.Blue)
              .onChange((isOn: boolean) => {
                if (isOn) {
                  this.isFull = 'true';
                  saveIsfull(this.isFull);
                } else {
                  this.isFull = 'false';
                  saveIsfull(this.isFull);
                }
                this.setSystemFull(this.isFull, this.isHidestatus, this.isHidebar);
              })
          }

          Row() {
            Text("显示状态栏")
              .fontColor($r('app.color.dialog_text'))
              .width("35%")
              .height(32)
            Text()
              .width('50%')
            Toggle({
              type: ToggleType.Switch,
              isOn: this.get_isHideStatus()
            })
              .width('15%')
              .height(25)
              //.selectedColor(Color.Blue)
              .onChange((isOn: boolean) => {
                if (isOn) {
                  this.isHidestatus = 'true';
                  saveIshidestatus(this.isHidestatus);
                } else {
                  this.isHidestatus = 'false';
                  saveIshidestatus(this.isHidestatus);
                }
                //this.setSystemStatus(this.isHidestatus);
                this.setSystemFull(this.isFull, this.isHidestatus, this.isHidebar);
              })
          }

          Row() {
            Text("显示底部白条")
              .fontColor($r('app.color.dialog_text'))
              .width("35%")
              .height(32)
            Text()
              .width('50%')
            Toggle({
              type: ToggleType.Switch,
              isOn: this.get_isHideBar()
            })
              .width('15%')
              .height(25)
              //.selectedColor(Color.Blue)
              .onChange((isOn: boolean) => {
                if (isOn) {
                  this.isHidebar = 'true';
                  saveIshidebar(this.isHidebar);
                } else {
                  this.isHidebar = 'false';
                  saveIshidebar(this.isHidebar);
                }
                //this.setSystemBar(this.isHidebar);
                this.setSystemFull(this.isFull, this.isHidestatus, this.isHidebar);
              })
          }


          Row() {
            Text("强制深色模式")
              .fontColor($r('app.color.dialog_text'))
              .width("35%")
              .height(32)
            Text()
              .width('50%')
            Toggle({
              type: ToggleType.Switch,
              isOn: this.get_isWebDark()
            })
              .width('15%')
              .height(25)
              .onChange((isOn: boolean) => {
                this.webDark = isOn ? 'dark' : 'auto';
                saveWebDarkMode(this.webDark);
                this.lastTopBg = '';
                this.lastBottomBg = '';
                this.applyImmersiveTheme('', '', true);
                this.refreshWeb();
              })
          }

          Row() {
            Text("伪装 TapTap 客户端")
              .fontColor($r('app.color.dialog_text'))
              .width("35%")
              .height(32)
            Text()
              .width('50%')
            Toggle({
              type: ToggleType.Switch,
              isOn: this.fakeAppUa === 'true'
            })
              .width('15%')
              .height(25)
              .onChange((isOn: boolean) => {
                this.fakeAppUa = isOn ? 'true' : 'false';
                saveFakeAppUa(this.fakeAppUa);
                this.change_userAgent();
                this.refreshWeb();
              })
          }

          Row() {
            Text("下拉灵敏度")
              .fontColor($r('app.color.dialog_text'))
              .width("30%")
              .height(32)
            Text()
              .width('10%')
            Slider({
              value: this.slide_num * 100,
              step: 10,
              min: 10,
              style: SliderStyle.InSet
            })
              .width('50%')
              .height(25)
              .showSteps(true)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.slide_num = value / 100;
                saveSlidenum(value / 100);
              })
            Text((this.slide_num * 100).toFixed(0))
              .width('10%')
              .height(32)
              .textAlign(TextAlign.End)

          }


          Row()
            .height(30)

          Row() {
            Text("Version:1.2.9")
              .fontColor($r('app.color.dialog_text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
          }


          Row()
            .height(20)

          Row() {
            Button('返回')
              .type(ButtonType.Capsule)
              //.backgroundColor(Color.Blue)
              .onClick(() => {
                this.showSetting = false
                this.c_ua_temp = this.c_pg_ua;
                //this.cancelRefresh()
                //this.refreshWeb();
              })
              .height(40)
              .width(100)
          }

        }
        .width("90%")
        //.height("70%")
        .padding(20)
        .backgroundColor($r('app.color.panel_bg'))
        .borderRadius($r('sys.float.corner_radius_level8'))
      }
      .width("100%")
      .height("100%")
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Color.Transparent)
      .visibility(this.showSetting ? Visibility.Visible : Visibility.None)

      // 长按菜单点击遮罩（点击空白关闭）
      if (this.ctxVisible) {
        Column()
          .width('100%')
          .height('100%')
          .onClick(() => {
            this.ctxVisible = false;
          })
      }

      // 长按图片/视频 自绘上下文菜单（参考 aira-browser 自绘 overlay 方案）
      if (this.ctxVisible) {
        Column() {
          ForEach(this.ctxItems, (item: string) => {
            Text(item)
              .fontSize(15)
              .fontColor($r('app.color.dialog_text'))
              .height(44)
              .width(170)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.onCtxItem(item);
              })
            if (item !== this.ctxItems[this.ctxItems.length - 1]) {
              Divider()
                .color($r('app.color.ctx_divider'))
                .width(150)
            }
          }, (item: string) => item)
        }
        .backgroundColor($r('app.color.ctx_menu_bg'))
        .borderRadius(12)
        .shadow({ radius: 16, color: '#26000000' })
        .position({ x: this.ctxX, y: this.ctxY })
      }

    }
    .height('100%')
    .width('100%')

  }

  onBackPress() {
    // 当前页面是否可前进或者后退给定的step步(-1),正数代表前进，负数代表后退
    if (this.controller.accessStep(-1)) {
      this.controller.backward(); // 返回上一个web页
      // 执行用户自定义返回逻辑
      return true
    } else {
      // 执行系统默认返回逻辑，返回上一个page页
      return false
    }
  }

  onRefreshing() {
    // 清除已有定时器
    //this.clearRefreshTimer();
    // 设置新的定时器
    this.refreshTimerId = setTimeout(() => {
      this.list = Array(20).fill(Date.now());
      this.refreshing = false;

      if (!this.is_home) {
        this.refreshWeb();
        this.is_home = false;
        promptAction.showToast({ message: '刷新成功' });
      }
    }, 1000);
  }

  // 统一清除定时器方法
  private clearRefreshTimer() {
    if (this.refreshTimerId !== null) {
      clearTimeout(this.refreshTimerId);
      this.refreshTimerId = null;
    }
  }

  private refreshWeb() {
    if (this.isRefreshing) {
      return;
    }
    this.isRefreshing = true;
    // 重置发布器桌面 UA / 纯 Web 页 UA 强制标记，onLoadIntercept 会按当前 URL 重新判定
    this.uaForcedDesktop = false;
    this.uaForcedWeb = false;
    // 执行刷新
    this.controller.refresh();

    //刷新完成后恢复
    setTimeout(() => {
      // this.translateY = 0;
      this.isRefreshing = false;
    }, 1000);
  }

  // 中断刷新函数
  private cancelRefresh() {
    this.clearRefreshTimer(); // 统一清除
    this.isRefreshing = true;
    this.refreshing = true;
    this.controller.stop();
  }

  // 返回首页
  backToHome() {
    // 这里可以改为你的首页路由
    this.controller.loadUrl(this.saved_home_url);
  }

  // 用系统/外部应用打开非网页协议链接（如应用深链 taptap:// 等）
  async openExternalApp(url: string) {
    const uiContext = getContext(this) as common.UIAbilityContext;
    try {
      // 优先走系统链接分发（Deep Linking / App Linking），可拉起注册了该协议的应用
      let linkOptions: OpenLinkOptions = { appLinkingOnly: false };
      await uiContext.openLink(url, linkOptions);
    } catch (e) {
      // 兜底：显式构造 Want 拉起
      try {
        let want: Want = {
          action: 'ohos.want.action.viewData',
          uri: url
        };
        await uiContext.startAbility(want);
      } catch (err) {
        promptAction.showToast({ message: '未找到可以打开此链接的应用' });
      }
    }
  }

  get_isWebDark(): boolean {
    return this.webDark === 'dark';
  }

  /** 长按网页图片/视频 -> 接管系统菜单，弹自绘菜单（移植自 aira-browser 长按上下文菜单方案） */
  handleWebContextMenu(event: OnContextMenuShowEvent): boolean {
    try {
      if (!event || !event.param) {
        return false;
      }
      const param = event.param;
      let mediaType: number = -1;
      try {
        mediaType = Number(param.getMediaType());
      } catch (err) {
        mediaType = -1;
      }
      let sourceUrl: string = '';
      try {
        sourceUrl = param.getSourceUrl() || '';
      } catch (err) {
        sourceUrl = '';
      }
      let xPx: number = 0;
      let yPx: number = 0;
      try {
        xPx = Number(param.x());
        yPx = Number(param.y());
      } catch (err) {
        xPx = 0;
        yPx = 0;
      }
      // 图片/视频之外的（纯文本、普通区域）走系统默认
      if (mediaType !== 1 && mediaType !== 2 && mediaType !== 3) {
        return false;
      }
      if (!sourceUrl) {
        return false;
      }
      this.ctxUrl = sourceUrl;
      if (mediaType === 1) {
        this.ctxItems = ['保存图片', '复制图片链接'];
      } else {
        this.ctxItems = ['复制视频链接', '其他应用打开'];
      }
      // 坐标 px -> vp，并夹在屏幕内（菜单约 170vp 宽）
      const screenWVp: number = px2vp(display.getDefaultDisplaySync().width);
      const screenHVp: number = px2vp(display.getDefaultDisplaySync().height);
      this.ctxX = Math.min(Math.max(px2vp(xPx), 8), Math.max(screenWVp - 178, 8));
      this.ctxY = Math.min(Math.max(px2vp(yPx), 8), Math.max(screenHVp - 140, 8));
      if (event.result) {
        try {
          event.result.closeContextMenu();
        } catch (err) {
        }
      }
      this.ctxVisible = true;
      return true;
    } catch (err) {
      return false;
    }
  }

  onCtxItem(item: string): void {
    this.ctxVisible = false;
    const url = this.ctxUrl;
    if (item === '保存图片') {
      let cookie: string = '';
      try {
        cookie = webview.WebCookieManager.fetchCookieSync(url) || '';
      } catch (err) {
        cookie = '';
      }
      let pageUrl: string = '';
      try {
        pageUrl = this.controller.getUrl() || '';
      } catch (err) {
        pageUrl = '';
      }
      WebImageSaver.saveToGallery(context_index, url, pageUrl, cookie, this.userAgent);
    } else if (item === '复制图片链接' || item === '复制视频链接') {
      WebImageSaver.copyText(url, '已复制链接');
    } else if (item === '其他应用打开') {
      this.openExternalApp(url);
    }
  }

  /** 是否深色模式：开启强制深色，或系统当前为深色 */
  private isDarkModeNow(): boolean {
    if (this.webDark === 'dark') {
      return true;
    }
    try {
      if (context_index.config?.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK) {
        return true;
      }
    } catch (err) {
    }
    return false;
  }

  /** 亮度反转（HSV 的 V 取反、降饱和）：用于强制深色渲染时把浅色采样色转成深色 */
  private darkenSample(hex: string): string {
    const r = parseInt(hex.substring(1, 3), 16) / 255;
    const g = parseInt(hex.substring(3, 5), 16) / 255;
    const b = parseInt(hex.substring(5, 7), 16) / 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const v = max;
    const sv = max === 0 ? 0 : (max - min) / max;
    let h = 0;
    if (max !== min) {
      const d = max - min;
      if (max === r) {
        h = (g - b) / d + (g < b ? 6 : 0);
      } else if (max === g) {
        h = (b - r) / d + 2;
      } else {
        h = (r - g) / d + 4;
      }
      h /= 6;
    }
    const v2 = 1 - v;
    const s2 = Math.min(1, sv * 0.6);
    const i = Math.floor(h * 6);
    const f = h * 6 - i;
    const p = v2 * (1 - s2);
    const q = v2 * (1 - f * s2);
    const t = v2 * (1 - (1 - f) * s2);
    let r2 = 0;
    let g2 = 0;
    let b2 = 0;
    switch (i % 6) {
      case 0: r2 = v2; g2 = t; b2 = p; break;
      case 1: r2 = q; g2 = v2; b2 = p; break;
      case 2: r2 = p; g2 = v2; b2 = t; break;
      case 3: r2 = p; g2 = q; b2 = v2; break;
      case 4: r2 = t; g2 = p; b2 = v2; break;
      default: r2 = v2; g2 = p; b2 = q; break;
    }
    const to2 = (x: number): string => {
      const n = Math.round(x * 255).toString(16);
      return n.length < 2 ? '0' + n : n;
    };
    return '#' + to2(r2) + to2(g2) + to2(b2);
  }

  /** 亮度判断：true=浅色背景（用深色图标） */
  private lumLight(hex: string): boolean {
    const r = parseInt(hex.substring(1, 3), 16);
    const g = parseInt(hex.substring(3, 5), 16);
    const b = parseInt(hex.substring(5, 7), 16);
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.6;
  }

  /** 系统栏样式：顶栏/底栏背景取页面采样色（全屏/非全屏均不固定），无采样时按深浅色兜底 */
  private async updateSystemBarStyle(topBg: string = '', bottomBg: string = ''): Promise<void> {
    try {
      const win = await window.getLastWindow(context_index);
      const dark = this.isDarkModeNow();
      let statusBarColor = dark ? '#FF1B1C21' : '#00000000';
      let statusContent = dark ? '#FFFFFFFF' : '#FF000000';
      let navigationBarColor = dark ? '#FF161920' : '#00000000';
      let navContent = '#FFFFFFFF';
      // 深色渲染下 DOM 采样仍是浅色主题原始色：浅色采样需反转成深色再上屏
      if (/^#[0-9a-fA-F]{6}$/.test(topBg)) {
        const effTop = dark && this.lumLight(topBg) ? this.darkenSample(topBg) : topBg;
        statusBarColor = '#FF' + effTop.substring(1);
        statusContent = this.lumLight(effTop) ? '#FF000000' : '#FFFFFFFF';
      }
      if (/^#[0-9a-fA-F]{6}$/.test(bottomBg)) {
        const effBottom = dark && this.lumLight(bottomBg) ? this.darkenSample(bottomBg) : bottomBg;
        navigationBarColor = '#FF' + effBottom.substring(1);
        navContent = this.lumLight(effBottom) ? '#FF000000' : '#FFFFFFFF';
      }
      win.setWindowSystemBarProperties({
        statusBarColor: statusBarColor,
        navigationBarColor: navigationBarColor,
        statusBarContentColor: statusContent,
        navigationBarContentColor: navContent,
        isStatusBarLightIcon: statusContent === '#FFFFFFFF'
      });
      // 避让区填充色与状态栏色保持一致（无采样时深色用顶栏色，浅色透明交给 panel_bg）
      let fillTop = '';
      if (/^#[0-9a-fA-F]{6}$/.test(topBg)) {
        fillTop = dark && this.lumLight(topBg) ? this.darkenSample(topBg) : topBg;
      } else {
        fillTop = dark ? '#1B1C21' : '';
      }
      if (fillTop !== this.topFillColor) {
        this.topFillColor = fillTop;
      }
    } catch (err) {
    }
  }

  /** 沉浸式取色：顶栏/底栏背景取页面色（不固定），图标按亮度自适应 */
  async applyImmersiveTheme(topBg: string, bottomBg: string = '', force: boolean = false): Promise<void> {
    if (!force && (!topBg || (topBg === this.lastTopBg && bottomBg === this.lastBottomBg))) {
      return;
    }
    if (topBg) {
      this.lastTopBg = topBg;
    }
    if (bottomBg) {
      this.lastBottomBg = bottomBg;
    }
    await this.updateSystemBarStyle(this.lastTopBg, this.lastBottomBg);
  }

  get_isLSRefresh() {
    if (this.isLSRefresh == 'true') {
      return true;
    } else {
      return false;
    }
  }

  get_isHideBar() {
    if (this.isHidebar == 'true') {
      return true;
    } else {
      return false;
    }
  }

  get_isHideStatus() {
    if (this.isHidestatus == 'true') {
      return true;
    } else {
      return false;
    }
  }

  get_isfull() {
    if (this.isFull == 'true') {
      return true;
    } else {
      return false;
    }
  }

  getuseragentbytype(type: string) {
    let default_userAgent = this.controller.getUserAgent();
    let mobile_userAgent = default_userAgent.replace('PC', 'Mobile').replace('PC', 'Phone');
    let pc_userAgent = default_userAgent.replace('Mobile', 'PC').replace('Phone', 'PC');
    let custom_userAgent = this.c_pg_ua;
    let ua: string = '';
    switch (type) {
      case 'Mobile':
        ua = mobile_userAgent;
        break;
      case 'PC':
        ua = pc_userAgent;
        break;
      case 'custom':
        ua = custom_userAgent;
        break;
      default:
        ua = 'error';
        break;
    }
    return ua;
  }

  /** 发布器/编辑器等仅 PC 适配的页面（移动网页端发布器官方未适配）：自动改用桌面 UA */
  private isPublisherUrl(url: string): boolean {
    try {
      if ((url || '').indexOf('taptap') < 0) {
        return false;
      }
      const pathStart = url.indexOf('/', url.indexOf('//') + 2);
      const path = pathStart >= 0 ? url.substring(pathStart) : '';
      return path.indexOf('/publisher') >= 0 || path.indexOf('/embed/ugc-editor') >= 0 ||
        path.indexOf('/topic/create') >= 0 || path.indexOf('/video/create') >= 0 ||
        path.indexOf('/question/create') >= 0;
    } catch (err) {
      return false;
    }
  }

  /** 纯 Web 体验页：poster 活动页（如原神角色查询）与网页云玩播放器。
   * 伪装 UA 会命中页面的“App 内”分支，走客户端专属桥导致无法进入/无按钮；
   * 进入时临时摘除 TapTap 标识按普通浏览器加载，离开发自动恢复 */
  private isWebOnlyUrl(url: string): boolean {
    try {
      if ((url || '').indexOf('taptap') < 0) {
        return false;
      }
      const pathStart = url.indexOf('/', url.indexOf('//') + 2);
      const path = pathStart >= 0 ? url.substring(pathStart) : '';
      return path.indexOf('/poster/') >= 0 || path.indexOf('/web-cloud-game') >= 0;
    } catch (err) {
      return false;
    }
  }

  change_userAgent() {
    let default_userAgent = this.controller.getUserAgent();
    let mobile_userAgent = default_userAgent.replace('PC', 'Mobile').replace('PC', 'Phone');
    let pc_userAgent = default_userAgent.replace('Mobile', 'PC').replace('Phone', 'PC');
    let custom_userAgent = this.c_pg_ua;

    if (this.ua_type == 'Mobile') {
      this.userAgent = mobile_userAgent;
    }
    if (this.ua_type == 'PC') {
      this.userAgent = pc_userAgent;
    }
    if (this.ua_type == 'custom') {
      this.userAgent = custom_userAgent;
    }
    // 伪装 TapTap 客户端：Mobile UA 附加 TapTap 标识，网页据此判定为 App 内环境（可领签到奖励等）
    if (this.fakeAppUa === 'true' && this.ua_type === 'Mobile' && this.userAgent.indexOf('TapTap/') < 0) {
      this.userAgent = this.userAgent + ' TapTap/2.83.0-rel_1000';
    }
    this.controller.setCustomUserAgent(this.userAgent);
  }
}