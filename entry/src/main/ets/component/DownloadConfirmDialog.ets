import { EventIdConstants } from '../contants/EventIdConstants'
import { WebDownloadFileHelper } from '../delegate/WebDownloadFileImpl'
import { EmitterUtil } from '../utiles/EmitterUtil'

@CustomDialog
export struct DownloadConfirmDialog {
  @State isDownloading: boolean = false
  @State downloadProgress: number = 0
  dialogController: CustomDialogController

  aboutToAppear(): void {
    EmitterUtil.on<number>(EventIdConstants.DOWNLOAD_PROGRESS_EVENT_ID, (event) => {
      if (!event.data) {
        return
      }
      this.downloadProgress = event.data
    })
  }

  aboutToDisappear(): void {
    EmitterUtil.off<number>(EventIdConstants.DOWNLOAD_PROGRESS_EVENT_ID, (event) => {
      //注销事件监听
    })
  }

  build() {
    Column() {
      if (this.isDownloading) {
        Column() {
          Text('下载中...')
            .fontSize(16)
            .lineHeight(20)
            .fontColor('#1A1A1A')
            .margin({ top: 24, bottom: 16 })
          Progress({ value: this.downloadProgress, type: ProgressType.Linear })
            .width('90%')
            .height(20)
        }
        .width('90%')
        .height(108)
        .borderRadius(24)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Color.White)
      } else {
        Column() {
          Text('是否下载该文件？')
            .fontSize(16)
            .lineHeight(20)
            .fontColor('#1A1A1A')
            .margin({ bottom: 16 })
          Row() {
            Button("取消")
              .onClick(() => {
                //关闭下载弹窗
                WebDownloadFileHelper.closeDownloadPopUpWindow()
              })
              .width(148)
              .height(40)
              .backgroundColor(Color.Transparent)
              .fontSize(16)
              .fontColor('#797B80')
            Line().width(1).height(24).backgroundColor('#f3f3f3')
            SaveButton({
              text: SaveDescription.DOWNLOAD,
              buttonType: ButtonType.Capsule
            })
              .width(148)
              .height(40)
              .backgroundColor(Color.White)
              .fontSize(16)
              .fontColor('#0A58F6')
              .onClick(async (event: ClickEvent, result: SaveButtonOnClickResult) => {
                if (result == SaveButtonOnClickResult.SUCCESS/* && WebDownloadFileHelper.webDownloadItem*/) {
                  this.isDownloading = true
                  // 传入一个下载路径，并开始下载。
                  // 如果传入一个不存在的路径，则会下载到默认/data/storage/el2/base/cache/web/目录。
                  WebDownloadFileHelper.startDownload()
                }
              })
          }
        }
        .width('90%')
        .height(108)
        .borderRadius(24)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Color.White)
      }

    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}