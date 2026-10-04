import { webview } from '@kit.ArkWeb';
import { promptAction, window, display, prompt } from '@kit.ArkUI';
import { common, Want, OpenLinkOptions } from '@kit.AbilityKit';
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
  getWebDarkMode
} from '../model/StorageService';
import { DownloadConfirmDialog } from '../component/DownloadConfirmDialog'
import { IAbstractDownloadHandler } from '../delegate/IWebDownloadFile'
import { WebDownloadFileHelper } from '../delegate/WebDownloadFileImpl'
import { EmitterUtil } from '../utiles/EmitterUtil'
import { http } from '@kit.NetworkKit';
import { fileIo as fs, ReadOptions, WriteOptions } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError, systemDateTime } from '@kit.BasicServicesKit';
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
  @Builder
  //构建自定义菜单及触发功能接口
  MenuBuilder() {
    Column() {
      Row()
        .height(10)
      Row(){
        Text('是否保存至图库')
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
          .backgroundColor(Color.White)
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
          .backgroundColor(Color.Grey)
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
    .backgroundColor(Color.White)
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
          await windowClass.setWindowLayoutFullScreen(false)
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
  }

  async aboutToAppear() {
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
        .backgroundColor('#F5F6F7')
        .justifyContent(FlexAlign.SpaceAround)
      }
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
                }
                return false;
              })

          }
          .width("100%")
          .height("100%")

        }

      }
      .pullDownRatio(this.slide_num * this.isdrag)
      .backgroundColor('#F5F6F7')
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
                this.refreshWeb();
              })
          }

          Row() {
            Text("下拉灵敏度")
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
            Text("Version:1.1.0")
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
        .backgroundColor('#F5F6F7')
        .borderRadius($r('sys.float.corner_radius_level8'))
      }
      .width("100%")
      .height("100%")
      .justifyContent(FlexAlign.Center)
      .backgroundColor(Color.Transparent)
      .visibility(this.showSetting ? Visibility.Visible : Visibility.None)

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
    //this.c_pg_ua =this.userAgent;
    this.controller.setCustomUserAgent(this.userAgent);
  }
}