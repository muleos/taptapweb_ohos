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
  saveBottomLift,
  getBottomLift,
  saveWebCookie,
  getWebCookie
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




@Entry
@Component
struct Index {
  private isRefreshing: boolean = false;
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

  private shouldClearCache: boolean = false;
  // Cookie 登录（v1.7.4）：设置面板粘贴网页版 Cookie 写入 WebView CookieStore
  @State savedCookie: string = '';
  @State cookieInput: string = '';
  private cookiePending: boolean = false;
  // 启动性能：Web 首帧 src 用普通属性（非 @State），偏好设置晚于首帧就绪时不再触发二次加载
  private firstSrc: string = 'https://www.taptap.cn/';
  // 首页信息流缓存（v1.7.6）：上次存盘的首页 HTML，启动时打底渲染减少闪烁；空串表示无缓存
  private homeCacheHtml: string = '';
  private captureHomeCacheTimerId: number | null = null;
  private webReady: boolean = false;
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
  // 非全屏布局下页面底栏抬高量(vp)：窗口不延伸到导航区时把网页视口整体上收，避免网页底栏贴屏/被小白条手势区压住
  @State bottomLiftVp: number = 0;
  // 底栏抬高设置值(0-30vp)：设置面板可调，非全屏布局时生效（bottomLiftVp 的来源）
  @State bottomLiftSetting: number = 28;
  // 全屏避让填充色：状态栏区域与页面顶部采样色一致，避免色差断层
  @State topFillColor: string = '';
  // 底栏抬高区填充色：与底部采样色一致（同状态栏避让的取色逻辑）
  @State bottomFillColor: string = '';
  // 主内容区实际高度(vp)：底栏抬高区渐变分段填充的锚点
  @State contentHeightVp: number = 0;
  // 状态栏原生高度(vp)：全屏布局下二三级页面的避让量来源
  private statusVp: number = 0;
  // 当前窗口是否为全屏布局（setWindowLayoutFullScreen(true) 后窗口延伸到状态栏下）
  private fullLayout: boolean = false;
  // 当前主文档 URL：用于区分首页一级界面（保持沉浸不避让）与二三级页面（避让状态栏）
  private pageUrl: string = '';
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
          await windowClass.setWindowLayoutFullScreen(true);
          this.fullLayout = true;
          await windowClass.setSpecificSystemBarEnabled('status', true, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', true, true);

        } else {
          await windowClass.setWindowLayoutFullScreen(true);
          this.fullLayout = true;
          await windowClass.setSpecificSystemBarEnabled('status', true, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', false, true);

        }
      } else {
        if (is_hidebar == 'true') {
          await windowClass.setWindowLayoutFullScreen(true);
          this.fullLayout = true;
          await windowClass.setSpecificSystemBarEnabled('status', false, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', true, true);

        } else {
          await windowClass.setWindowLayoutFullScreen(true);
          this.fullLayout = true;
          await windowClass.setSpecificSystemBarEnabled('status', false, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', false, true);

        }
      }
    } else {
      if (is_hidestatus == 'true') {
        if (is_hidebar == 'true') {
          // 小白条开启：必须全屏布局。非全屏布局下系统会把导航栏画成默认黑，
          // navigationBarColor 被忽略；全屏布局下窗口延伸到小白条下方，采样色可正常上屏
          await windowClass.setWindowLayoutFullScreen(true);
          this.fullLayout = true;
          await windowClass.setSpecificSystemBarEnabled('status', true, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', true, true);
        } else {
          await windowClass.setWindowLayoutFullScreen(false);
          this.fullLayout = false;
          await windowClass.setSpecificSystemBarEnabled('status', true, true);
          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', false, true);

        }
      } else {
        if (is_hidebar == 'true') {
          await windowClass.setWindowLayoutFullScreen(true);
          this.fullLayout = true;
          await windowClass.setSpecificSystemBarEnabled('status', false, true);

          await windowClass.setSpecificSystemBarEnabled('navigationIndicator', true, true);

        } else {
          await windowClass.setWindowLayoutFullScreen(false);
          this.fullLayout = false;
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
    // 状态栏原生高度：全屏布局下二三级页面避让用；非全屏布局窗口自动避让，不加 padding
    try {
      const area = windowClass.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusVp = px2vp(area.topRect.top);
    } catch (err) {
      this.statusVp = 0;
    }
    this.pageUrl = this.saved_home_url || '';
    this.updateSafeTop();
    // 底栏抬高：仅非全屏布局生效，抬高量取设置值；全屏布局下窗口自管导航区，抬高会留无意义空带
    this.applyBottomLift();
  }

  /** 底栏抬高量 = 设置值（0-30vp）；全屏布局恒 0 */
  private applyBottomLift(): void {
    const liftVp: number = this.fullLayout ? 0 : this.bottomLiftSetting;
    if (liftVp !== this.bottomLiftVp) {
      this.bottomLiftVp = liftVp;
    }
  }

  /** 渐变分段锚点：顶部避让区结束比例（0-1） */
  private topStop(): number {
    if (this.contentHeightVp <= 0 || this.safeTopVp <= 0) {
      return 0;
    }
    return Math.min(1, this.safeTopVp / this.contentHeightVp);
  }

  /** 渐变分段锚点：底部抬高区开始比例（0-1） */
  private bottomStop(): number {
    if (this.contentHeightVp <= 0 || this.bottomLiftVp <= 0) {
      return 1;
    }
    return Math.max(0, 1 - this.bottomLiftVp / this.contentHeightVp);
  }

  /** 一级界面判定：主文档 URL 与设置的主页一致（去 query/hash、归一尾斜杠）视为首页，保持沉浸不避让 */
  private isTopLevelUrl(url: string): boolean {
    try {
      const norm = (u: string): string => {
        let s = (u || '').split('#')[0].split('?')[0];
        if (s.length > 1 && s.endsWith('/')) {
          s = s.substring(0, s.length - 1);
        }
        return s;
      };
      const home = norm(this.saved_home_url);
      if (home === '') {
        return false;
      }
      return norm(url) === home;
    } catch (err) {
      return false;
    }
  }

  /** 按布局模式与页面层级计算避让量：仅全屏布局且非首页一级界面时避让状态栏 */
  private updateSafeTop(): void {
    const target: number = (this.fullLayout && this.statusVp > 0 && !this.isTopLevelUrl(this.pageUrl))
      ? this.statusVp : 0;
    if (target !== this.safeTopVp) {
      this.safeTopVp = target;
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
    // 启动性能：偏好读取并行化（原先 12 次串行 await，每次都阻塞一帧）
    const slidePromise = getSlidenum();
    const prefs: string[] = await Promise.all([
      getLSRefresh(), getUserAgent(), getHomeUrl(), getIshidebar(), getIshidestatus(),
      getUserAgentType(), getIsfull(), getWebDarkMode(), getBottomLift(), getWebCookie()
    ]);
    const slideN: number = await slidePromise;
    this.isLSRefresh = prefs[0] || this.isLSRefresh;
    this.c_pg_ua = prefs[1] || this.c_pg_ua;
    this.c_ua_temp = prefs[1] || this.c_pg_ua;
    this.saved_home_url = prefs[2] || this.saved_home_url;
    this.isHidebar = (prefs[3] || this.isHidebar);
    this.isHidestatus = (prefs[4] || this.isHidestatus);
    this.ua_type = (prefs[5] || this.ua_type);
    // 伪装 TapTap 客户端：设置面板开关已移除（v1.7.0），功能恒为默认开启；
    // 旧版本存过 'false' 的用户在此强制纠正，保证签到/云玩等 inApp 流程可用
    this.fakeAppUa = 'true';
    saveFakeAppUa('true');
    this.isFull = (prefs[6] || this.isFull);
    this.slide_num = slideN || this.slide_num;
    this.webDark = (prefs[7] || this.webDark);
    // 底栏抬高设置值(0-30vp)：默认 28，超界纠正
    const savedLift = Number(prefs[8] || '');
    this.bottomLiftSetting = isNaN(savedLift)
      ? 28
      : Math.max(0, Math.min(30, Math.round(savedLift)));
    // Cookie 登录：内核已在 EntryAbility 预热，首帧加载前写入可随首个请求生效；
    // 写入失败（内核未就绪）时置 pending，由 onControllerAttached 补写并刷新一次
    this.savedCookie = (prefs[9] || '').trim();
    if (this.savedCookie !== '' && !this.applyWebCookie()) {
      this.cookiePending = true;
    }
    // 启动性能：首帧 src 尚未被消费时直接用真实首页，避免"先默认页再跳转"的二次加载
    if (!this.webReady && this.saved_home_url) {
      this.firstSrc = this.saved_home_url;
    }
    // 首页信息流缓存（v1.7.6）：同步读上次存盘的首页 HTML（限 20KB~8MB、7 天内），
    // 有缓存则首帧用 about:blank 占位，onControllerAttached 里 loadData 缓存打底渲染，
    // 消除冷启动白屏闪烁；无缓存走真实首页加载
    try {
      const cachePath = (getContext(this) as common.UIAbilityContext).cacheDir + '/ttw_home_cache.html';
      const stat = fs.statSync(cachePath);
      if (stat.size > 20 * 1024 && stat.size <= 8 * 1024 * 1024 && Date.now() - stat.mtime < 7 * 24 * 3600 * 1000) {
        const cf = fs.openSync(cachePath, fs.OpenMode.READ_ONLY);
        const cbuf = new ArrayBuffer(stat.size);
        const copt: ReadOptions = { offset: 0, length: stat.size };
        fs.readSync(cf.fd, cbuf, copt);
        fs.closeSync(cf);
        this.homeCacheHtml = buffer.from(cbuf).toString();
      }
    } catch (err) {
      this.homeCacheHtml = '';
    }
    if (this.homeCacheHtml !== '') {
      this.firstSrc = 'about:blank';
    }

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
              this.controller.removeCache(true);
              // 同步清除首页信息流缓存（v1.7.6），避免显式清缓存后仍用旧打底页
              try {
                fs.unlinkSync((getContext(this) as common.UIAbilityContext).cacheDir + '/ttw_home_cache.html');
              } catch (err) {
              }
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
            Web({ src: this.firstSrc, controller: this.controller })
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
                // 首页信息流缓存打底（v1.7.6）：把上次缓存的首页 HTML 以首页为 baseUrl 灌入渲染，
                // 秒出信息流内容，页面脚本随后自行水合并拉取新数据；失败则回退真实首页加载
                if (this.homeCacheHtml !== '') {
                  const cachedHtml = this.homeCacheHtml;
                  this.homeCacheHtml = '';
                  const homeUrl = this.saved_home_url || 'https://www.taptap.cn/';
                  try {
                    this.controller.loadData(cachedHtml, 'text/html', 'utf-8', homeUrl, homeUrl);
                    this.pageUrl = homeUrl;
                    this.updateSafeTop();
                  } catch (err) {
                    try {
                      this.controller.loadUrl(homeUrl);
                    } catch (err2) {
                    }
                  }
                }
                // Cookie 登录兜底：aboutToAppear 时内核未就绪导致写入失败的，这里补写；
                // 补写成功后整页加载真实首页（缓存打底页若在则被替换），保证登录态随请求生效
                if (this.cookiePending) {
                  this.cookiePending = false;
                  if (this.applyWebCookie()) {
                    setTimeout(() => {
                      try {
                        this.controller.loadUrl(this.saved_home_url || 'https://www.taptap.cn/');
                      } catch (err) {
                      }
                    }, 300);
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
                    // 主文档导航：按页面层级刷新状态栏避让（首页沉浸，二三级避让）
                    this.pageUrl = url;
                    this.updateSafeTop();
                    const isPub = this.isPublisherUrl(url);
                    const isWebOnly = this.isWebOnlyUrl(url);
                    if (this.ua_type === 'Mobile') {
                      // 纯 Web 体验页（poster 活动页/网页云玩/第三方工具站）：临时摘除 TapTap 伪装标识，避免页面走客户端专属流
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
              .onPageEnd(() => {
                // 首页信息流缓存（v1.7.6）：页面加载完成后延迟采样整页 HTML 存盘，供下次启动打底
                this.captureHomeCache();
              })

          }
          .width("100%")
          .height("100%")
          // 顶部状态栏避让；底部：非全屏布局抬高（0-30vp 可调）让网页底栏离开屏幕下缘
          .padding({ top: this.safeTopVp, bottom: this.bottomLiftVp })
          // 避让/抬高区分段取色：上段用页面顶部采样色、下段用页面底部采样色（与系统栏同逻辑）；
          // 无采样时回退 panel_bg（浅色资源自适配深浅色）
          .linearGradient({
            angle: 180,
            colors: [
              [this.topFillColor === '' ? $r('app.color.panel_bg') : this.topFillColor, 0],
              [this.topFillColor === '' ? $r('app.color.panel_bg') : this.topFillColor, this.topStop()],
              [this.bottomFillColor === '' ? $r('app.color.panel_bg') : this.bottomFillColor, this.bottomStop()],
              [this.bottomFillColor === '' ? $r('app.color.panel_bg') : this.bottomFillColor, 1]
            ]
          })
          .onAreaChange((_oldArea: Area, newArea: Area) => {
            const h: number = Number(newArea.height) || 0;
            if (h > 0 && Math.abs(h - this.contentHeightVp) > 0.5) {
              this.contentHeightVp = h;
            }
          })

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
          // v1.7.9：设置页隐藏"首页"行（逻辑保留，仅 UI 不显示）
          .visibility(Visibility.None)

          Row()
            .height(10)
            .visibility(Visibility.None)

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
          // v1.7.9：设置页隐藏"UA"选择行（逻辑保留，仅 UI 不显示）
          .justifyContent(FlexAlign.SpaceAround)
          .width('100%')
          .visibility(Visibility.None)

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
          // v1.7.9：设置页隐藏自定义 UA 输入区（UA 行已隐藏，此区随之隐藏）
          .visibility(Visibility.None)

          //.alignItems(VerticalAlign.Top)
          Row()
            .height(10)
            .visibility(Visibility.None)

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

          Row() {
            Text("底栏抬高")
              .fontColor($r('app.color.dialog_text'))
              .width("30%")
              .height(32)
            Text()
              .width('10%')
            Slider({
              value: this.bottomLiftSetting,
              step: 1,
              min: 0,
              max: 30,
              style: SliderStyle.InSet
            })
              .width('50%')
              .height(25)
              .showSteps(true)
              .onChange((value: number, mode: SliderChangeMode) => {
                const v: number = Math.max(0, Math.min(30, Math.round(value)));
                if (v === this.bottomLiftSetting && mode !== SliderChangeMode.End) {
                  return;
                }
                this.bottomLiftSetting = v;
                saveBottomLift(String(v));
                // 非全屏布局立即生效；全屏布局自动忽略
                this.applyBottomLift();
              })
            Text(this.bottomLiftSetting.toFixed(0))
              .width('10%')
              .height(32)
              .textAlign(TextAlign.End)

          }


          Row()
            .height(30)

          Row() {
            Text("Version:1.7.4")
              .fontColor($r('app.color.dialog_text_secondary'))
              .width('100%')
              .textAlign(TextAlign.Center)
          }


          Row()
            .height(20)

          // 登录 Cookie（v1.7.4）：粘贴网页版 Cookie 写入 WebView CookieStore 获取登录态，
          // 替代 v1.7.1 的"登录 TapTap"跳转按钮（云玩按钮数据/第三方工具授权都依赖登录态）
          Row() {
            Text('登录 Cookie')
              .fontColor($r('app.color.dialog_text'))
              .width('30%')
              .height(40)
            TextInput({
              placeholder: '粘贴网页版 Cookie',
              text: this.cookieInput
            })
              .height(40)
              .layoutWeight(1)
              .fontSize(13)
              .onChange((value: string) => {
                this.cookieInput = value;
              })

            Button('应用')
              .type(ButtonType.Capsule)
              .backgroundColor($r('app.color.dialog_text_secondary'))
              .margin({ left: 8 })
              .height(40)
              .width(72)
              .onClick(() => {
                const raw = (this.cookieInput || '').trim();
                if (raw === '') {
                  promptAction.showToast({ message: '请先粘贴 Cookie 串' });
                  return;
                }
                this.savedCookie = raw;
                saveWebCookie(raw);
                const ok = this.applyWebCookie();
                this.showSetting = false;
                if (ok) {
                  promptAction.showToast({ message: 'Cookie 已写入，刷新登录态' });
                  this.refreshWeb();
                } else {
                  this.cookiePending = true;
                  promptAction.showToast({ message: '内核未就绪，页面加载时自动重试' });
                }
              })
          }
          .width('100%')

          // 获取当前账号 Cookie（v1.7.5）：应用内已登录时一键取出 WebView 现有登录 Cookie，
          // 填入上方输入框供查看/复制，再点"应用"固化到双域（与手动粘贴输入并存）
          Row() {
            Text('应用内已登录时，可一键取出当前登录 Cookie')
              .fontSize(11)
              .fontColor($r('app.color.dialog_text_secondary'))
              .layoutWeight(1)
            Button('获取当前 Cookie')
              .type(ButtonType.Capsule)
              .backgroundColor($r('app.color.dialog_text_secondary'))
              .height(32)
              .fontSize(12)
              .onClick(() => {
                const got = this.fetchCurrentCookie();
                if (got === '') {
                  promptAction.showToast({ message: '未取到 Cookie，请先在应用内登录' });
                  return;
                }
                this.cookieInput = got;
                promptAction.showToast({ message: '已填入当前 Cookie，点"应用"生效' });
              })
          }
          .width('100%')
          .margin({ top: 8 })

          Row()
            .height(16)

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
    // 启动性能：当前已在目标首页（首帧 src 命中）时跳过，避免同 URL 重复加载
    try {
      const target = this.saved_home_url || 'https://www.taptap.cn/';
      let current = '';
      try {
        current = this.controller.getUrl() || '';
      } catch (e) {
        current = '';
      }
      // 首页缓存打底流程中：about:blank 占位页等待 onControllerAttached 灌入缓存，不抢跳首页
      if (current === 'about:blank' && this.homeCacheHtml !== '') {
        return;
      }
      if (current !== '' && current === target) {
        return;
      }
      this.controller.loadUrl(target);
    } catch (err) {
    }
  }

  /** 首页信息流缓存（v1.7.6）：仅首页信息流参与缓存打底 */
  private isHomeUrl(url: string): boolean {
    const home = (this.saved_home_url || 'https://www.taptap.cn/').trim();
    if (url === '' || home === '') {
      return false;
    }
    return url === home || url.split('?')[0] === home.split('?')[0];
  }

  /** 首页加载完成后延迟 3.5s 采样整页 HTML 存盘（等信息流渲染稳定）；期间离开首页则放弃 */
  private captureHomeCache() {
    if (this.captureHomeCacheTimerId !== null) {
      clearTimeout(this.captureHomeCacheTimerId);
      this.captureHomeCacheTimerId = null;
    }
    this.captureHomeCacheTimerId = setTimeout(() => {
      this.captureHomeCacheTimerId = null;
      try {
        if (!this.isHomeUrl(this.pageUrl)) {
          return;
        }
        this.controller.runJavaScript('document.documentElement.outerHTML').then((html: string) => {
          this.saveHomeCache(html);
        }).catch(() => {
        });
      } catch (err) {
      }
    }, 3500);
  }

  private async saveHomeCache(html: string) {
    try {
      if (!html || html.length < 50 * 1024 || html.length > 8 * 1024 * 1024) {
        return;
      }
      if (!this.isHomeUrl(this.pageUrl)) {
        return;
      }
      const cachePath = (getContext(this) as common.UIAbilityContext).cacheDir + '/ttw_home_cache.html';
      const f = await fs.open(cachePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(f.fd, html);
      await fs.close(f);
    } catch (err) {
    }
  }

  /** 获取当前账号 Cookie（v1.7.5）：从 WebView CookieStore 读出 taptap.cn 与
   * accounts.taptap.cn 两个域的现有 Cookie，按名称去重合并（账号域后写、覆盖主站同名项，
   * 保证登录态优先），拼成 k=v; k=v 串返回。空串表示取不到（未登录/内核未就绪） */
  private fetchCurrentCookie(): string {
    const names: string[] = [];
    const values: string[] = [];
    const sources: string[] = ['https://www.taptap.cn', 'https://accounts.taptap.cn'];
    for (let s = 0; s < sources.length; s++) {
      let raw = '';
      try {
        raw = webview.WebCookieManager.fetchCookieSync(sources[s]) || '';
      } catch (err) {
        raw = '';
      }
      const parts = raw.split(';');
      for (let i = 0; i < parts.length; i++) {
        const kv = parts[i].trim();
        const eq = kv.indexOf('=');
        if (eq <= 0) {
          continue;
        }
        const name = kv.substring(0, eq).trim();
        const value = kv.substring(eq + 1).trim();
        if (name === '' || value === '') {
          continue;
        }
        let idx = -1;
        for (let j = 0; j < names.length; j++) {
          if (names[j] === name) {
            idx = j;
            break;
          }
        }
        if (idx >= 0) {
          values[idx] = value;
        } else {
          names.push(name);
          values.push(value);
        }
      }
    }
    let out = '';
    for (let j = 0; j < names.length; j++) {
      out = out + (out === '' ? '' : '; ') + names[j] + '=' + values[j];
    }
    return out;
  }

  /** Cookie 登录（v1.7.4）：把用户粘贴的网页版 Cookie 串逐对写入
   * taptap.cn / accounts.taptap.cn 域，写入后随请求自动携带。
   * 返回是否成功写入；串为空返回 false（不置 pending） */
  private applyWebCookie(): boolean {
    const raw = (this.savedCookie || '').trim();
    if (raw === '') {
      return false;
    }
    let ok = false;
    try {
      const parts = raw.split(';');
      for (let i = 0; i < parts.length; i++) {
        const kv = parts[i].trim();
        if (kv.indexOf('=') <= 0) {
          continue;
        }
        try {
          webview.WebCookieManager.configCookieSync('https://www.taptap.cn', kv);
          webview.WebCookieManager.configCookieSync('https://accounts.taptap.cn', kv);
          ok = true;
        } catch (err) {
        }
      }
    } catch (e) {
      return false;
    }
    return ok;
  }

  // 用系统/外部应用打开非网页协议链接（如应用深链 taptap:// 等）
  async openExternalApp(url: string) {
    const uiContext = getContext(this) as common.UIAbilityContext;
    try {
      // 优先走系统链接分发（Deep Linking / App Linking），可拉起注册了该协议的应用
      let linkOptions: OpenLinkOptions = { appLinkingOnly: false };
      await uiContext.openLink(url, linkOptions);
      return;
    } catch (e) {
    }
    try {
      // 兜底：显式构造 Want 拉起
      let want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      };
      await uiContext.startAbility(want);
      return;
    } catch (err) {
    }
    // 壳内兜底（v1.7.5）：本机没有应用接手 taptap:// 深链时（未装 TapTap 客户端的常态），
    // 尝试把深链还原成等价 https 页面在壳内继续打开——活动页"前往查看"、工具箱工具项
    // 这类死路按钮大多带 url= / path= / app_id= 参数，可无损映射回网页版
    const fallback = this.taptapDeepLinkToFallback(url);
    if (fallback !== '') {
      promptAction.showToast({ message: '正在打开网页版' });
      this.controller.loadUrl(fallback);
      return;
    }
    promptAction.showToast({ message: '未找到可以打开此链接的应用' });
  }

  /** taptap:// 深链 -> 等价 https 链接（v1.7.5）。
   * 仅做无损失的参数还原：url=（内层 http 链接）、path=（站内路径）、app_id=（详情页）。
   * 还原不了（纯客户端原生页）返回空串，由调用方提示前往客户端 */
  private taptapDeepLinkToFallback(url: string): string {
    try {
      if (!url || url.indexOf('taptap://') !== 0) {
        return '';
      }
      // 角色查询/游戏数据页深链（game_record/detail）：还原为网页版数据页
      // /user/<uid>/game-record/<app_id>（uid 取登录后的 user_id Cookie），未登录引导登录页
      if (url.indexOf('game_record/detail') >= 0) {
        const mApp = url.match(/[?&]app_id=(\d+)/);
        if (mApp && mApp.length > 1) {
          let uid = '';
          try {
            const ck = webview.WebCookieManager.fetchCookieSync('https://www.taptap.cn') || '';
            const mUid = ck.match(/user_id=(\d+)/);
            if (mUid && mUid.length > 1) {
              uid = mUid[1];
            }
          } catch (e) {
          }
          if (uid !== '') {
            return 'https://www.taptap.cn/user/' + uid + '/game-record/' + mApp[1];
          }
          return 'https://www.taptap.cn/login';
        }
      }
      const qIdx = url.indexOf('?');
      if (qIdx < 0) {
        return '';
      }
      const parts = url.substring(qIdx + 1).split('&');
      let innerUrl = '';
      let path = '';
      let appId = '';
      for (let i = 0; i < parts.length; i++) {
        const kv = parts[i];
        const eq = kv.indexOf('=');
        if (eq <= 0) {
          continue;
        }
        const key = kv.substring(0, eq).toLowerCase();
        let val = kv.substring(eq + 1);
        try {
          val = decodeURIComponent(val.replace(/\+/g, ' '));
        } catch (e) {
        }
        if (key === 'url' && val.indexOf('http') === 0 && innerUrl === '') {
          innerUrl = val;
        } else if (key === 'path' && val.length > 0 && path === '') {
          path = val;
        } else if (key === 'app_id' && val.length > 0 && appId === '') {
          let digits = true;
          for (let d = 0; d < val.length; d++) {
            if (val.charAt(d) < '0' || val.charAt(d) > '9') {
              digits = false;
              break;
            }
          }
          if (digits) {
            appId = val;
          }
        }
      }
      if (innerUrl !== '') {
        return innerUrl;
      }
      if (path.charAt(0) === '/') {
        return 'https://www.taptap.cn' + path;
      }
      if (appId !== '') {
        return 'https://www.taptap.cn/app/' + appId;
      }
    } catch (err) {
    }
    return '';
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
      // 底栏抬高区填充色：与导航栏/底部采样色同一逻辑（无采样时深色用底栏色，浅色交给 panel_bg）
      let fillBottom = '';
      if (/^#[0-9a-fA-F]{6}$/.test(bottomBg)) {
        fillBottom = dark && this.lumLight(bottomBg) ? this.darkenSample(bottomBg) : bottomBg;
      } else {
        fillBottom = dark ? '#161920' : '';
      }
      if (fillBottom !== this.bottomFillColor) {
        this.bottomFillColor = fillBottom;
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

  /** 纯 Web 体验页：poster 活动页（如原神角色查询）、登录/OAuth 页。
   * 伪装 UA 会命中页面的“App 内”分支，走客户端专属桥导致无法进入/无按钮；
   * 进入时临时摘除 TapTap 标识按普通浏览器加载，离开发自动恢复。
   * v1.7.3：/web-cloud-game 回退——网页云玩按钮数据依赖登录态且体验不稳，不再特殊路由 */
  private isWebOnlyUrl(url: string): boolean {
    try {
      const hostStart = (url || '').indexOf('//');
      const host = hostStart >= 0
        ? url.substring(hostStart + 2, url.indexOf('/', hostStart + 2) >= 0 ? url.indexOf('/', hostStart + 2) : url.length).toLowerCase()
        : '';
      // 非 TapTap 站点（游戏工具箱的第三方工具 H5、OAuth 页等）：一律纯浏览器 UA，
      // 避免伪装标识让工具页误判处于 TapTap 客户端而调用不存在的桥
      if (host !== '' && host.indexOf('taptap') < 0) {
        return true;
      }
      // TapTap 账号/OAuth 域（accounts.taptap.cn）：伪装 UA + 假桥未登录会卡"扫码登录"墙，
      // 按普通浏览器加载网页版登录（手机验证码/密码），登录 cookie 与主站共享
      if (host.indexOf('accounts.taptap') >= 0) {
        return true;
      }
      if ((url || '').indexOf('taptap') < 0) {
        return false;
      }
      const pathStart = url.indexOf('/', url.indexOf('//') + 2);
      const path = pathStart >= 0 ? url.substring(pathStart) : '';
      return path.indexOf('/poster/') >= 0 ||
        path.indexOf('/login') >= 0 || path.indexOf('/oauth') >= 0;
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