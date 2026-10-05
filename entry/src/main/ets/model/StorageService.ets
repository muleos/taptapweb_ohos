import preferences from '@ohos.data.preferences';

let prefs: preferences.Preferences;

async function getPreferences() {
  if (!prefs) {
    prefs = await preferences.getPreferences(globalThis.getContext(), 'app_config');
  }
  return prefs;
}

export async function saveHomeUrl(page_url: string) {
  const store = await getPreferences();
  await store.put('homepage_url', page_url);
  await store.flush(); // 刷新保存
}

export async function getHomeUrl(): Promise<string> {
  const store = await getPreferences();
  return String(await store.get('homepage_url', ''));
}

export async function saveUserAgent(page_ua: string) {
  const store = await getPreferences();
  await store.put('c_userAgent', page_ua);
  await store.flush(); // 刷新保存
}

export async function getUserAgent(): Promise<string> {
  const store = await getPreferences();
  return String(await store.get('c_userAgent', ''));
}

export async function saveUserAgentType(page_ua_type: string) {
  const store = await getPreferences();
  await store.put('userAgent_type', page_ua_type);
  await store.flush(); // 刷新保存
}

export async function getUserAgentType(): Promise<string> {
  const store = await getPreferences();
  return String(await store.get('userAgent_type', ''));
}

export async function saveLSRefresh(LSRefresh: string) {
  const store = await getPreferences();
  await store.put('is_lsr', LSRefresh);
  await store.flush(); // 刷新保存
}

export async function getLSRefresh(): Promise<string> {
  const store = await getPreferences();
  return String(await store.get('is_lsr', ''));
}

export async function saveIshidebar(ishidebar: string) {
  const store = await getPreferences();
  await store.put('is_hidebar', ishidebar);
  await store.flush(); // 刷新保存
}

export async function getIshidebar(): Promise<string> {
  const store = await getPreferences();
  return String(await store.get('is_hidebar', ''));
}

export async function saveIshidestatus(ishidestatus: string) {
  const store = await getPreferences();
  await store.put('is_hidestatus', ishidestatus);
  await store.flush(); // 刷新保存
}

export async function getIshidestatus(): Promise<string> {
  const store = await getPreferences();
  return String(await store.get('is_hidestatus', ''));
}

export async function saveIsfull(isfull: string) {
  const store = await getPreferences();
  await store.put('is_full', isfull);
  await store.flush(); // 刷新保存
}

export async function getIsfull(): Promise<string> {
  const store = await getPreferences();
  return String(await store.get('is_full', ''));
}

export async function saveSlidenum(slidenum: number) {
  const store = await getPreferences();
  await store.put('slide_num', slidenum);
  await store.flush(); // 刷新保存
}

export async function getSlidenum(): Promise<number> {
  const store = await getPreferences();
  return Number(await store.get('slide_num', 0));
}

export async function saveWebDarkMode(mode: string) {
  const store = await getPreferences();
  await store.put('web_dark_mode', mode);
  await store.flush(); // 刷新保存
}

export async function getWebDarkMode(): Promise<string> {
  const store = await getPreferences();
  return String(await store.get('web_dark_mode', ''));
}

export async function saveFakeAppUa(v: string) {
  const store = await getPreferences();
  await store.put('fake_app_ua', v);
  await store.flush();
}

export async function getFakeAppUa(): Promise<string> {
  const store = await getPreferences();
  return String(await store.get('fake_app_ua', ''));
}

export async function saveBottomLift(v: string) {
  const store = await getPreferences();
  await store.put('bottom_lift', v);
  await store.flush();
}

export async function getBottomLift(): Promise<string> {
  const store = await getPreferences();
  return String(await store.get('bottom_lift', ''));
}

// Cookie 登录（v1.7.4）：持久化用户粘贴的网页版 Cookie 串，启动时重放进 WebView CookieStore
export async function saveWebCookie(v: string) {
  const store = await getPreferences();
  await store.put('web_cookie', v);
  await store.flush();
}

export async function getWebCookie(): Promise<string> {
  const store = await getPreferences();
  return String(await store.get('web_cookie', ''));
}
