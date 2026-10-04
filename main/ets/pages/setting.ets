import { promptAction, window, display, SelectTitleBar } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import {
  saveHomeUrl,
  getHomeUrl,
  saveUserAgent,
  getUserAgent,
  saveLSRefresh,
  getLSRefresh
} from '../model/StorageService';


let context_index = getContext(this) as common.UIAbilityContext;
let resourceDir = context_index.resourceDir;

@Entry
@Component
struct Index {
  @State home_url: string = ''
  @State saved_home_url: string = 'https://www.taptap.cn/';
  @State c_pg_ua: string =
    'Mozilla/5.0 (Linux; Android 8.0.0; SM-G955U Build/R16NW) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36 HarveyHarmonyOS/1.0.0';
  @State isLSRefresh: string = 'true'; //是否横屏不能刷新

  async aboutToAppear() {
    this.isLSRefresh = await getLSRefresh() || this.isLSRefresh;
    this.c_pg_ua = await getUserAgent() || this.c_pg_ua;
    this.saved_home_url = await getHomeUrl() || this.saved_home_url;
  }

  @Builder
  content() {
    Stack() {
      Column() {
        Row() {

        }

      }
    }

  }

  build() {
    NavDestination() {


    }

  }
}