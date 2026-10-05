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
;(function () {
  // 伪造 TapTap 客户端 JSBridge：UA 含 TapTap 时向页面提供 window.TapTapAPI。
  // TapTap 活动页（game-sign 等）的 inApp 检测只看该对象是否存在，不解析 UA；
  // 检测通过后页面渲染真实签到 UI，签到/领奖由页面自身 XHR + web 会话 cookie 完成。
  // 版本门禁读取桥方法 tapEnv() 的 VN_CODE（需 >= 293000000，否则弹"需要最新版本客户端"）。
  if ((navigator.userAgent || '').indexOf('TapTap') < 0) { return; }
  var pp = location.pathname || '';
  // 发布器/编辑器页走 PC 模式（原生层已切桌面 UA），不注入客户端桥，保持纯浏览器环境
  if (pp.indexOf('/publisher') >= 0 || pp.indexOf('/embed/ugc-editor') >= 0 ||
      pp.indexOf('/topic/create') >= 0 || pp.indexOf('/video/create') >= 0 ||
      pp.indexOf('/question/create') >= 0) { return; }
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
//# sourceURL=ttw-web-chrome.js
`;
