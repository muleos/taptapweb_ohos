/**
 * WebChromeScript.ets
 * 注入到每个页面 document-start 的 JS：
 * 沉浸式取色探针：采样页面顶部/底部背景色，经 console 上报给原生（__TTW_CHROME__）
 * 参考实现：aira-browser HostedWebNode 页面主题探针
 */

export const WEB_CHROME_SCRIPT: string = `
;(function () {
  // 伪造 TapTap 客户端 JSBridge（必须放在所有 IIFE 最前：同一注入脚本内任何后续
  // IIFE 顶层抛出未捕获异常都会中断其后所有语句，桥必须最先就位，否则活动页
  // （game-sign 等）inApp 检测失败会退回"去客户端领取"模式）。
  // TapTap 活动页的 inApp 检测只看 window.TapTapAPI 或 window.urlResource.TapTapAPI
  // 是否存在，不解析 UA；检测通过后页面渲染真实签到/领取 UI，签到/领奖由页面自身
  // XHR + web 会话 cookie 完成。版本门禁读取桥方法 tapEnv() 的 VN_CODE。
  // 注入范围：taptap 主站一律注入（不依赖原生 UA 附加是否成功）；纯浏览器语境页
  // （登录/OAuth/海报活动页/发布器/编辑器）不注入，避免页面走客户端专属流。
  try {
    var ttwHost = (location.hostname || '');
    var ttwPath = location.pathname || '';
    var ttwTapHost = ttwHost.indexOf('taptap.cn') >= 0 || ttwHost.indexOf('taptap.com') >= 0;
    if (!ttwTapHost && (navigator.userAgent || '').indexOf('TapTap') < 0) { return; }
    if (ttwHost.indexOf('accounts.') === 0) { return; }
    if (ttwPath.indexOf('/poster/') === 0 || ttwPath.indexOf('/login') === 0 ||
        ttwPath.indexOf('/oauth') === 0) { return; }
    if (ttwPath.indexOf('/publisher') >= 0 || ttwPath.indexOf('/embed/ugc-editor') >= 0 ||
        ttwPath.indexOf('/topic/create') >= 0 || ttwPath.indexOf('/video/create') >= 0 ||
        ttwPath.indexOf('/question/create') >= 0) { return; }
    if (window.TapTapAPI) { return; }
    var ttwBridge = function ttwBridge(name, payload) { return undefined; };
    try {
      delete ttwBridge.name;
      delete ttwBridge.length;
    } catch (e0) { }
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
    // 登录态：web 会话有 user_id cookie 即视为已登录，页面 XHR 走同源会话完成真实鉴权
    ttwBridge.getClientLoginState = function () {
      try {
        return /(?:^|;\\s*)user_id=\\d+/.test(document.cookie) ? '1' : '0';
      } catch (e1) { return '0'; }
    };
    window.TapTapAPI = ttwBridge;
    try {
      window.urlResource = window.urlResource || {};
      window.urlResource.TapTapAPI = window.urlResource.TapTapAPI || {};
    } catch (e2) { }
  } catch (ttwBridgeErr) { }
})();
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
  // 页面不可见时跳过采样，降低后台 CPU/电量开销
  setInterval(function () { if (!document.hidden) { scheduleTheme(); } }, 2000);
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
      // 顶部绿色胶囊下载按钮：v1.7.0 逆向确认头部按钮为 a/div.main-layout-header__download-client
      // （border-radius:100px 胶囊、--phone 变体 accent 绿底白字），可见文案是“下载手机 APP”
      // 而非“下载App”，旧文字匹配从未命中。按类名精确命中按钮本体，不伤及同行标语。
      // v1.7.3：部分页面（如首页）头部按钮类名前缀一致但组件不同，放宽为 class 前缀匹配
      var caps = document.querySelectorAll('[class*="download-client"]');
      for (var c = 0; c < caps.length; c++) {
        var cap = caps[c];
        if (!cap || cap.getAttribute('data-ttw-hidden')) { continue; }
        cap.style.setProperty('display', 'none', 'important');
        cap.setAttribute('data-ttw-hidden', '1');
      }
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
        // 下载 App：只隐藏按钮本体。v1.7.3 允许 div 但要求后代节点极少（按钮级），
        // 整行横幅（logo/标语为图片、行文案恰为“下载App”）后代多不会误伤；
        // “发现好游戏”字样出现时一律跳过（顶栏守卫行）
        if (text === '下载App' || text === '下载APP' || text === '下载手机APP') {
          if (text.indexOf('发现好游戏') >= 0) { continue; }
          var tg = (el.tagName || '').toLowerCase();
          if (tg === 'a' || tg === 'button' || tg === 'span' || tg === 'div') {
            var desc = 0;
            try { desc = el.querySelectorAll('*').length; } catch (eD) { }
            if (desc <= 8) {
              el.style.setProperty('display', 'none', 'important');
              el.setAttribute('data-ttw-hidden', '1');
            }
          }
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
  // 页面不可见时跳过扫描，降低后台 CPU 开销
  setInterval(function () { if (!document.hidden) { hideTaptapPromos(); } }, 1500);
  scheduleHide();
})();
// 伪造客户端桥 IIFE 已移至脚本最前（见文件头部），此处不再重复注入
;(function () {
  // 发布器/编辑器页伪装 PC 环境：TapTap 移动网页端发布器未适配（页面自述“主要面向电脑端使用”），
  // 桌面 UA 由原生层按 URL 自动切换；此处补齐 JS 层：去除 Android userAgentData、触摸特征置零
  var pubPath = location.pathname || '';
  if (pubPath.indexOf('/publisher') < 0 && pubPath.indexOf('/embed/ugc-editor') < 0 &&
      pubPath.indexOf('/topic/create') < 0 && pubPath.indexOf('/video/create') < 0 &&
      pubPath.indexOf('/question/create') < 0) { return; }
  try {
    Object.defineProperty(navigator, 'userAgentData', { get: function () { return undefined; }, configurable: true });
  } catch (e) { }
  try {
    Object.defineProperty(navigator, 'maxTouchPoints', { get: function () { return 0; }, configurable: true });
  } catch (e) { }
  try {
    Object.defineProperty(navigator, 'msMaxTouchPoints', { get: function () { return 0; }, configurable: true });
  } catch (e) { }
  try {
    var ttwOrigMatch = window.matchMedia ? window.matchMedia.bind(window) : null;
    if (ttwOrigMatch) {
      window.matchMedia = function (q) {
        var m = ttwOrigMatch(q);
        try {
          var qs = String(q || '');
          if (qs.indexOf('pointer: coarse') >= 0 || qs.indexOf('pointer:coarse') >= 0 ||
              qs.indexOf('hover: none') >= 0 || qs.indexOf('hover:none') >= 0) {
            var fake = Object.create(m);
            fake.matches = false;
            return fake;
          }
        } catch (e2) { }
        return m;
      };
    }
  } catch (e) { }
})();
;(function () {
  // 顶栏守卫：确保“TapTap 发现好游戏”行始终可见。
  // ① 兜底解除本脚本历史上误标记的整行隐藏（data-ttw-hidden 且文案含“发现好游戏”）；
  // ② 页面加载完成后回到顶部一次，修复顶栏停在视口之上、需手动下拉才能看到的问题
  if ((navigator.userAgent || '').indexOf('TapTap') < 0) { return; }
  if (window.__ttwHeaderGuardInstalled) { return; }
  window.__ttwHeaderGuardInstalled = 1;

  function unhideMarkedRows() {
    if ((location.hostname || '').indexOf('taptap') < 0) { return; }
    try {
      var marked = document.querySelectorAll('[data-ttw-hidden]');
      for (var i = 0; i < marked.length; i++) {
        var el = marked[i];
        var text = (el.textContent || '').replace(/\\s+/g, '');
        if (text.indexOf('发现好游戏') >= 0) {
          el.removeAttribute('data-ttw-hidden');
          el.style.setProperty('display', '', 'important');
        }
      }
    } catch (e) { }
  }

  var topped = false;
  function backToTopOnce() {
    if (topped) { return; }
    topped = true;
    try { window.scrollTo(0, 0); } catch (e) { }
  }

  window.addEventListener('load', function () { unhideMarkedRows(); backToTopOnce(); });
  window.addEventListener('pageshow', function () { unhideMarkedRows(); });
  setInterval(unhideMarkedRows, 1500);
  unhideMarkedRows();
})();
;(function () {
  // 引导区去点击化：顶栏“TapTap 发现好游戏 / 下载 App”横幅、底部“打开 App 关注游戏”条等
  // 只保留展示，不再响应点击——原点击会弹“前往 TapTap 客户端”弹窗或唤起深链（v1.7.3）。
  // 捕获阶段拦截，命中引导文案即吞掉事件；元素本身不移除、不隐藏。
  if ((navigator.userAgent || '').indexOf('TapTap') < 0) { return; }
  if (window.__ttwPromoInertInstalled) { return; }
  window.__ttwPromoInertInstalled = 1;

  function ttwPromoText(el) {
    var t = '';
    try {
      t = (el.textContent || '') + ' ' + ((el.getAttribute && el.getAttribute('aria-label')) || '');
    } catch (e) { }
    return t.replace(/\\s+/g, '');
  }

  // 组合容器判定：元素含多个各自带文字的直接子节点（如底部条"论坛|活动|打开App关注游戏"）。
  // 这类容器的合并文案即使命中引导词，也只拦截其中的引导按钮本体，不能整条去点击化——
  // 否则会误伤同条内的论坛/活动等正常功能入口（v1.7.3 回归原因）
  function ttwIsComposite(el) {
    try {
      var kids = el.children || [];
      var withText = 0;
      for (var k = 0; k < kids.length; k++) {
        if ((kids[k].textContent || '').replace(/\\s+/g, '')) {
          withText++;
          if (withText >= 2) { return true; }
        }
      }
    } catch (e) { }
    return false;
  }

  document.addEventListener('click', function (e) {
    try {
      if ((location.hostname || '').indexOf('taptap') < 0) { return; }
      var el = e.target;
      for (var i = 0; el && i < 8; i++, el = el.parentElement) {
        var text = ttwPromoText(el);
        if (!text) { continue; }
        var hit = false;
        if (text === '发现好游戏' || text === 'TapTap发现好游戏' ||
            text === '下载App' || text === '下载APP' || text === '下载手机APP' ||
            text === '打开App关注游戏' || text === '打开APP关注游戏') {
          hit = true;
        } else if (text.length <= 16 &&
                   (text.indexOf('打开App') >= 0 || text.indexOf('打开APP') >= 0 ||
                    text.indexOf('打开TapTap') >= 0 || text.indexOf('TapTap内打开') >= 0) &&
                   !ttwIsComposite(el)) {
          hit = true;
        }
        if (hit) {
          e.preventDefault();
          e.stopPropagation();
          return;
        }
      }
    } catch (err) { }
  }, true);
})();
;(function () {
  // 游戏工具箱修复：/tools 页工具项点击时——
  // ① taptap:// 开头的 uri 直接弹"请前往 TapTap 客户端使用"（壳内死路）；
  // ② 其余走 window.open(url,"_blank")，壳的 WebView 未开启多窗口，静默失效。
  // 修复：
  //  A. 拦截 game-tool 接口响应，把 taptap:// 深链还原成等价 https 链接写回 web_url；
  //  B. 在 TapTap 站点内把 window.open 改写为当前窗口导航（多窗口不可用时的通用兜底，
  //     同时修复工具箱、侧栏外链等所有 _blank 点击无响应的问题）。
  if ((location.hostname || '').indexOf('taptap') < 0) { return; }
  if (window.__ttwToolsFixInstalled) { return; }
  window.__ttwToolsFixInstalled = 1;

  function ttwIsToolApi(u) {
    return (u || '').indexOf('/game-tool/v1/all-tools') >= 0 ||
      (u || '').indexOf('/game-tool/v1/app-tools') >= 0;
  }

  function ttwFixTool(t) {
    if (!t || typeof t !== 'object') { return; }
    var u = String(t.web_url || t.uri || '');
    if (!u || u.indexOf('http') === 0) { return; }
    if (u.indexOf('taptap://') !== 0) { return; }
    var m = u.match(/[?&]url=([^&]+)/);
    if (m) {
      try {
        var dec = decodeURIComponent(m[1]);
        if (dec.indexOf('http') === 0) { t.web_url = dec; return; }
      } catch (e1) { }
    }
    // 角色查询类深链（game_record/detail）：还原成网页版数据页
    // /user/<uid>/game-record/<app_id>（uid 在登录后由主站种在 user_id Cookie）；
    // 未登录则引导到登录页（不能用 app_id 降级为详情页，那不是数据页）
    if (u.indexOf('game_record/detail') >= 0) {
      var gm = u.match(/[?&]app_id=(\\d+)/);
      if (gm) {
        var um = document.cookie.match(/(?:^|;\\s*)user_id=(\\d+)/);
        t.web_url = um ? ('https://www.taptap.cn/user/' + um[1] + '/game-record/' + gm[1])
                       : 'https://www.taptap.cn/login';
        return;
      }
    }
    var a = u.match(/[?&]app_id=(\\d+)/);
    if (a) { t.web_url = 'https://www.taptap.cn/app/' + a[1]; return; }
    var p = u.match(/[?&]path=([^&]+)/);
    if (p) {
      try {
        var path = decodeURIComponent(p[1]);
        if (path.indexOf('/') === 0) { t.web_url = 'https://www.taptap.cn' + path; return; }
      } catch (e2) { }
    }
  }

  function ttwRewriteToolsJson(txt) {
    try {
      var d = JSON.parse(txt);
      var roots = [d, d && d.data];
      for (var i = 0; i < roots.length; i++) {
        var arr = roots[i] && roots[i].tools;
        if (arr && arr.length) {
          for (var j = 0; j < arr.length; j++) { ttwFixTool(arr[j]); }
        }
      }
      return JSON.stringify(d);
    } catch (e) { return txt; }
  }

  // A. 响应改写：fetch
  try {
    var ttwOrigFetch = window.fetch;
    if (ttwOrigFetch) {
      window.fetch = function (input) {
        var u = '';
        try { u = (typeof input === 'string') ? input : (input && input.url) || ''; } catch (e0) { }
        var pr = ttwOrigFetch.apply(this, arguments);
        if (u && ttwIsToolApi(u)) {
          return pr.then(function (res) {
            try {
              return res.clone().text().then(function (t) {
                return new Response(ttwRewriteToolsJson(t), { status: res.status, statusText: res.statusText, headers: res.headers });
              });
            } catch (e1) { return res; }
          });
        }
        return pr;
      };
    }
  } catch (e) { }
  // A. 响应改写：XHR
  try {
    var ttwOrigOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (m, u) {
      try { this.__ttwUrl = String(u || ''); } catch (e0) { }
      return ttwOrigOpen.apply(this, arguments);
    };
    var ttwOrigSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.send = function () {
      var xhr = this;
      if (xhr.__ttwUrl && ttwIsToolApi(xhr.__ttwUrl)) {
        var props = ['responseText', 'response'];
        for (var k = 0; k < props.length; k++) {
          (function (prop) {
            try {
              var desc = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, prop);
              if (!desc || !desc.get) { return; }
              Object.defineProperty(xhr, prop, {
                get: function () {
                  var v = desc.get.call(xhr);
                  return (typeof v === 'string' && v.charAt(0) === '{') ? ttwRewriteToolsJson(v) : v;
                },
                configurable: true
              });
            } catch (e1) { }
          })(props[k]);
        }
      }
      return ttwOrigSend.apply(this, arguments);
    };
  } catch (e) { }
  // B. window.open → 当前窗口导航（仅 TapTap 站内）
  try {
    window.open = function (u) {
      try {
        var t = String(u || '');
        if (t.indexOf('http') === 0 || t.indexOf('/') === 0) {
          window.location.href = t;
        }
      } catch (e0) { }
      return null;
    };
  } catch (e) { }
})();
;(function () {
  // game-record 海报页修复：官方「前往查看」按钮的处理函数以 IS_IN_TAPTAP 为前提，
  // 纯浏览器/壳内环境点击无任何动作（官方网页端即如此）；其本应去往的网页版数据页为
  // /user/<uid>/game-record/<app_id>，uid 可从登录后的 user_id Cookie 取得。
  // 仅作用于 /poster/game-record/ 路径，避免影响其他活动海报的正常按钮。
  if ((location.hostname || '').indexOf('taptap') < 0) { return; }
  if (window.__ttwPosterRecordFixInstalled) { return; }
  window.__ttwPosterRecordFixInstalled = 1;
  function ttwGoGameRecord() {
    try {
      var app = '';
      try {
        app = String((window.moo && window.moo.getLocaleMessage && window.moo.getLocaleMessage('custom.app_id')) || '');
      } catch (e0) { }
      if (!app && window.moo && window.moo.dataPool && window.moo.dataPool.__default) {
        try {
          app = String(window.moo.dataPool.__default.custom.app_id || '');
        } catch (e1) { }
      }
      var um = document.cookie.match(/(?:^|;\\s*)user_id=(\\d+)/);
      if (um && app) {
        window.location.href = 'https://www.taptap.cn/user/' + um[1] + '/game-record/' + app;
        return;
      }
      window.location.href = 'https://www.taptap.cn/login';
    } catch (e2) { }
  }
  document.addEventListener('click', function (e) {
    try {
      if (location.pathname.indexOf('/poster/game-record/') !== 0) { return; }
      var el = e.target;
      for (var i = 0; el && i < 8; i++, el = el.parentElement) {
        var t = String(el.textContent || '').replace(/\\s+/g, '');
        if (t === '前往查看') {
          e.preventDefault();
          e.stopPropagation();
          ttwGoGameRecord();
          return;
        }
        if (t === '登录去查看') {
          e.preventDefault();
          e.stopPropagation();
          window.location.href = 'https://www.taptap.cn/login';
          return;
        }
      }
    } catch (err) { }
  }, true);
})();
;(function () {
  // 礼包兑换码领取修复：官方网页端礼包卡片「领取」按钮移动端无点击处理、桌面端仅弹
  // 「请到 TapTap 客户端领取」对话框（即用户看到的跳转 app 提示）。但领取接口
  // POST /webapiv2/app/v1/game-number/delivery-for-hoverboard（参数 id=礼包id，CSRF 用
  // XSRF-TOKEN Cookie 双提交 x-xsrf-token 头）在登录态下同源可调。礼包数据来自
  // GET /webapiv2/app-news/v1/list?app_id=... 的 activity_list[].game_number_list。
  // 仅拦截礼包卡片（gift-item 胶囊 / 含"礼包兑换码"文案 / gifts-news-item 行），
  // 签到、活动等其他卡片不受影响。
  if ((location.hostname || '').indexOf('taptap') < 0) { return; }
  if (window.__ttwGiftClaimInstalled) { return; }
  window.__ttwGiftClaimInstalled = 1;
  function ttwCookie(name) {
    var m = document.cookie.match(new RegExp('(?:^|;\\s*)' + name + '=([^;]*)'));
    return m ? m[1] : '';
  }
  function ttwToast(msg) {
    try {
      var t = document.createElement('div');
      t.textContent = msg;
      t.style.cssText = 'position:fixed;left:50%;bottom:20%;transform:translateX(-50%);z-index:2147483647;background:rgba(0,0,0,.75);color:#fff;padding:10px 16px;border-radius:8px;font-size:14px;max-width:80vw;text-align:center;';
      document.body.appendChild(t);
      setTimeout(function () { t.remove(); }, 2600);
    } catch (e0) { }
  }
  function ttwCopy(text) {
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(text); return; }
    } catch (e1) { }
    try {
      var ta = document.createElement('textarea');
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      ta.remove();
    } catch (e2) { }
  }
  function ttwShowCode(label, sn) {
    try {
      var ov = document.createElement('div');
      ov.style.cssText = 'position:fixed;left:0;top:0;right:0;bottom:0;z-index:2147483646;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;';
      var box = document.createElement('div');
      box.style.cssText = 'background:#fff;border-radius:12px;padding:20px;width:78vw;max-width:340px;text-align:center;';
      var h = document.createElement('div');
      h.textContent = label || '礼包兑换码';
      h.style.cssText = 'font-size:16px;font-weight:700;color:#222;margin-bottom:10px;';
      var code = document.createElement('div');
      code.textContent = sn;
      code.style.cssText = 'font-size:18px;font-weight:700;color:#ff6b00;letter-spacing:1px;margin-bottom:14px;word-break:break-all;';
      var row = document.createElement('div');
      row.style.cssText = 'display:flex;gap:10px;justify-content:center;';
      var cp = document.createElement('button');
      cp.textContent = '复制兑换码';
      cp.style.cssText = 'flex:1;padding:10px 0;border:none;border-radius:8px;background:#00c3a0;color:#fff;font-size:14px;';
      cp.onclick = function () { ttwCopy(sn); ttwToast('已复制'); };
      var cl = document.createElement('button');
      cl.textContent = '关闭';
      cl.style.cssText = 'flex:1;padding:10px 0;border:none;border-radius:8px;background:#f2f2f2;color:#333;font-size:14px;';
      cl.onclick = function () { ov.remove(); };
      row.appendChild(cp);
      row.appendChild(cl);
      box.appendChild(h);
      box.appendChild(code);
      box.appendChild(row);
      ov.appendChild(box);
      document.body.appendChild(ov);
    } catch (e3) { }
  }
  function ttwXua() {
    var uid = ttwCookie('web_app_uuid') || 'd8f3a1c2b4e54f6789a0b1c2d3e4f5a6';
    return 'V=1&PN=Web&LANG=zh_CN&VN_CODE=100000000&LOC=CN&PLT=Android&DS=Android&UID=' + uid + '&OS=Android&OSV=14';
  }
  function ttwApi(path, opts) {
    var q = path + (path.indexOf('?') >= 0 ? '&' : '?') + 'X-UA=' + encodeURIComponent(ttwXua());
    return fetch(q, opts || {}).then(function (r) { return r.json(); });
  }
  function ttwClaimGift(cardText) {
    var m = location.pathname.match(/\/app\/(\d+)/);
    var appId = m ? m[1] : '';
    if (!appId) { ttwToast('请在游戏详情页领取礼包'); return; }
    ttwToast('正在领取礼包…');
    ttwApi('/webapiv2/app-news/v1/list?app_id=' + appId + '&preview=false').then(function (j) {
      var list = (j && j.data && j.data.activity_list) || [];
      var gifts = [];
      list.forEach(function (it) {
        if ((it.label_type === 'gift' || it.type === 'gift') && it.game_number_list) {
          it.game_number_list.forEach(function (g) { gifts.push(g); });
        }
      });
      if (!gifts.length) { ttwToast('当前没有可领取的礼包'); return; }
      var target = null;
      gifts.forEach(function (g) { if (!target && g.label && cardText.indexOf(g.label) >= 0) { target = g; } });
      if (!target) { gifts.forEach(function (g) { if (!target && !g.sn) { target = g; } }); }
      if (!target) { target = gifts[0]; }
      if (target.sn) { ttwShowCode(target.label, target.sn); return; }
      var headers = { 'Content-Type': 'application/x-www-form-urlencoded', 'x-requested-with': 'XMLHttpRequest' };
      var xsrf = ttwCookie('XSRF-TOKEN');
      if (xsrf) { headers['x-xsrf-token'] = xsrf; }
      ttwApi('/webapiv2/app/v1/game-number/delivery-for-hoverboard', {
        method: 'POST',
        headers: headers,
        body: 'id=' + target.id
      }).then(function (j2) {
        if (j2 && j2.success) {
          ttwApi('/webapiv2/app-news/v1/list?app_id=' + appId + '&preview=false').then(function (j3) {
            var sn = '';
            ((j3 && j3.data && j3.data.activity_list) || []).forEach(function (it) {
              (it.game_number_list || []).forEach(function (g) {
                if (g.id === target.id && g.sn) { sn = g.sn; }
              });
            });
            if (sn) { ttwShowCode(target.label, sn); } else { ttwToast('领取成功，可在游戏内兑换'); }
          }).catch(function () { ttwToast('领取成功'); });
        } else {
          var msg = (j2 && j2.data && j2.data.msg) || '';
          ttwToast(msg || '领取失败，请先在设置中登录');
        }
      }).catch(function () { ttwToast('领取失败，请确认已登录'); });
    }).catch(function () { ttwToast('活动数据加载失败'); });
  }
  document.addEventListener('click', function (e) {
    try {
      if (location.pathname.indexOf('/app/') !== 0) { return; }
      var el = e.target;
      for (var i = 0; el && i < 10; i++, el = el.parentElement) {
        var cls = ' ' + (typeof el.className === 'string' ? el.className : '') + ' ';
        var isNewsCard = cls.indexOf(' news-card-item ') >= 0;
        var isGiftRow = cls.indexOf(' gifts-news-item ') >= 0;
        if (!isNewsCard && !isGiftRow) { continue; }
        // 已展示兑换码的行（含复制按钮）不拦截，避免破坏复制操作
        if (isGiftRow && el.querySelector('.gifts-news-item__sn')) { return; }
        var text = String(el.textContent || '');
        var isGift = cls.indexOf(' gift-item ') >= 0 || text.indexOf('礼包兑换码') >= 0 || isGiftRow;
        if (!isGift) { return; }
        e.preventDefault();
        e.stopPropagation();
        ttwClaimGift(text.replace(/\\s+/g, ''));
        return;
      }
    } catch (err) { }
  }, true);
})();
//# sourceURL=ttw-web-chrome.js
`;
