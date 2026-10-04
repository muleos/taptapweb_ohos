/**
 * WebChromeScript.ets
 * 注入到每个页面 document-start 的 JS：
 * 沉浸式取色探针：采样页面顶部/底部背景色，经 console 上报给原生（__TTW_CHROME__）
 * 参考实现：aira-browser HostedWebNode 页面主题探针
 */

export const WEB_CHROME_SCRIPT: string = `
;(function () {
  if (window.__ttwChromeInstalled) { return; }
  window.__ttwChromeInstalled = 1;

  /* ---------------- 取色探针 ---------------- */
  var lastBg = '';
  var lastBbg = '';

  function toHex(value) {
    var normalized = String(value || '').trim();
    if (!normalized) { return ''; }
    var probe = document.createElement('span');
    probe.style.color = '';
    probe.style.color = normalized;
    if (!probe.style.color) { return ''; }
    (document.body || document.documentElement).appendChild(probe);
    var resolved = window.getComputedStyle(probe).color || '';
    probe.remove();
    var match = resolved.match(/rgba?\\(([^)]+)\\)/i);
    if (!match) { return ''; }
    var parts = match[1].split(',');
    var alpha = parts.length > 3 ? parseFloat(parts[3]) : 1;
    if (alpha < 0.5) { return ''; }
    function ch(x) {
      var n = parseInt(x, 10);
      if (isNaN(n)) { return 0; }
      return Math.max(0, Math.min(255, n));
    }
    function hx(x) {
      var s = ch(x).toString(16);
      return s.length < 2 ? '0' + s : s;
    }
    return '#' + hx(parts[0]) + hx(parts[1]) + hx(parts[2]);
  }

  function cssAlpha(color) {
    var m = String(color || '').match(/rgba?\\(([^)]+)\\)/i);
    if (!m) { return 1; }
    var parts = m[1].split(',');
    return parts.length > 3 ? parseFloat(parts[3]) : 1;
  }

  function sampleTopBackground() {
    try {
      var metas = document.querySelectorAll('meta[name="theme-color"]');
      for (var i = metas.length - 1; i >= 0; i--) {
        var content = metas[i].getAttribute('content') || '';
        var mm = content.match(/#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\\b/);
        if (mm) {
          var mc = toHex(mm[0]);
          if (mc) { return mc; }
        }
      }
      var vw = Math.max(document.documentElement.clientWidth || 0, window.innerWidth || 1);
      var stack = document.elementsFromPoint ? document.elementsFromPoint(vw / 2, 10) : [];
      var candidates = stack.slice(0, 8);
      candidates.push(document.body, document.documentElement);
      for (var j = 0; j < candidates.length; j++) {
        var el = candidates[j];
        var hops = 0;
        while (el && hops < 6) {
          var cs = window.getComputedStyle(el);
          var bg = cs.backgroundColor;
          if (bg && cssAlpha(bg) >= 0.5) {
            var resolved = toHex(bg);
            if (resolved) { return resolved; }
          }
          el = el.parentElement;
          hops++;
        }
      }
    } catch (e) { }
    return '';
  }

  function sampleBottomBackground() {
    try {
      var vw = Math.max(document.documentElement.clientWidth || 0, window.innerWidth || 1);
      var vh = Math.max(document.documentElement.clientHeight || 0, window.innerHeight || 1);
      var stack = document.elementsFromPoint ? document.elementsFromPoint(vw / 2, vh - 10) : [];
      var candidates = stack.slice(0, 8);
      candidates.push(document.body, document.documentElement);
      for (var j = 0; j < candidates.length; j++) {
        var el = candidates[j];
        var hops = 0;
        while (el && hops < 6) {
          var cs = window.getComputedStyle(el);
          var bg = cs.backgroundColor;
          if (bg && cssAlpha(bg) >= 0.5) {
            var resolved = toHex(bg);
            if (resolved) { return resolved; }
          }
          el = el.parentElement;
          hops++;
        }
      }
    } catch (e) { }
    return '';
  }

  function sendTheme() {
    try {
      var bg = sampleTopBackground();
      var bbg = sampleBottomBackground();
      if ((!bg || bg === lastBg) && (!bbg || bbg === lastBbg)) { return; }
      if (bg && bg !== lastBg) { lastBg = bg; }
      if (bbg && bbg !== lastBbg) { lastBbg = bbg; }
      console.info('__TTW_CHROME__' + JSON.stringify({ bg: bg, bbg: bbg }));
    } catch (e) { }
  }

  var themeTimer = null;
  function scheduleTheme() {
    if (themeTimer) { return; }
    themeTimer = setTimeout(function () { themeTimer = null; sendTheme(); }, 300);
  }


  /* ---------------- 安装观察器 ---------------- */
  try {
    new MutationObserver(scheduleTheme).observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['class', 'style', 'data-theme', 'data-color-mode', 'data-color-scheme']
    });
  } catch (e) { }
  try {
    new MutationObserver(scheduleTheme).observe(document.head, { childList: true, subtree: true });
  } catch (e) { }

  function installBodyObservers() {
    if (!document.body) { return; }
    try {
      new MutationObserver(scheduleTheme).observe(document.body, {
        childList: true, subtree: true, attributes: true, attributeFilter: ['class', 'style']
      });
    } catch (e) { }
  }

  if (document.body) {
    installBodyObservers();
  } else {
    document.addEventListener('DOMContentLoaded', function () {
      installBodyObservers();
      scheduleTheme();
    }, { once: true });
  }

  window.addEventListener('load', function () { scheduleTheme(); });
  window.addEventListener('pageshow', function () { scheduleTheme(); });
  setInterval(scheduleTheme, 2000);
  scheduleTheme();
})();
;(function () {
  // 伪装 TapTap 客户端时（UA 含 TapTap）隐藏"打开 TapTap 客户端"类引导按钮
  if ((navigator.userAgent || '').indexOf('TapTap') < 0) { return; }
  if (window.__ttwPromoHideInstalled) { return; }
  window.__ttwPromoHideInstalled = 1;

  function hideUp(el) {
    try {
      var target = null;
      var p = el;
      var hops = 0;
      while (p && hops < 6) {
        var cs = window.getComputedStyle(p);
        if (cs && (cs.position === 'fixed' || cs.position === 'absolute')) { target = p; }
        p = p.parentElement;
        hops++;
      }
      if (!target) { target = el; }
      target.style.setProperty('display', 'none', 'important');
      target.setAttribute('data-ttw-hidden', '1');
    } catch (e) { }
  }

  function isTaptapHost() {
    return (location.hostname || '').indexOf('taptap') >= 0;
  }

  function hideTaptapPromos() {
    if (!isTaptapHost()) { return; }
    try {
      var all = document.querySelectorAll('div,a,button,span,section,footer,header,aside');
      for (var i = 0; i < all.length; i++) {
        var el = all[i];
        if (!el || el.getAttribute('data-ttw-hidden')) { continue; }
        var text = (el.textContent || '').replace(/\\s+/g, '');
        if (!text || text.length > 30) { continue; }
        if (text.indexOf('打开TapTap') >= 0 || text.indexOf('TapTap内打开') >= 0 ||
            text === 'App内打开' || text === '打开App') {
          hideUp(el);
          continue;
        }
        if ((text === '下载App' || text === '下载APP') && el.children.length <= 3) {
          hideUp(el);
        }
      }
    } catch (e) { }
  }

  var hideTimer = null;
  function scheduleHide() {
    if (hideTimer) { return; }
    hideTimer = setTimeout(function () { hideTimer = null; hideTaptapPromos(); }, 400);
  }

  try {
    new MutationObserver(scheduleHide).observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) { }
  window.addEventListener('load', scheduleHide);
  window.addEventListener('pageshow', scheduleHide);
  setInterval(hideTaptapPromos, 1500);
  scheduleHide();
})();
;(function () {
  // 伪造 TapTap 客户端 JSBridge：UA 含 TapTap 时向页面提供 window.TapTapAPI。
  // TapTap 活动页（game-sign 等）的 inApp 检测只看该对象是否存在，不解析 UA；
  // 检测通过后页面渲染真实签到 UI，签到/领奖由页面自身 XHR + web 会话 cookie 完成。
  // 版本门禁读取桥方法 tapEnv() 的 VN_CODE（需 >= 293000000，否则弹"需要最新版本客户端"）。
  if ((navigator.userAgent || '').indexOf('TapTap') < 0) { return; }
  if (window.TapTapAPI) { return; }
  function ttwBridge(name, payload) { return undefined; }
  try {
    delete ttwBridge.name;
    delete ttwBridge.length;
  } catch (e) { }
  ttwBridge.tapEnv = function () {
    return JSON.stringify({
      PN: 'android',
      VN: '2.94.0',
      VN_CODE: '294000000',
      LANG: 'zh_CN',
      SAFE_AREA_INSET_TOP: 0
    });
  };
  ttwBridge.getSMDeviceId = function () { return ''; };
  ttwBridge.getClientLoginState = function () { return '0'; };
  window.TapTapAPI = ttwBridge;
})();
//# sourceURL=ttw-web-chrome.js
`;
