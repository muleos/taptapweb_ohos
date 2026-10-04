/**
 * WebChromeScript.ets
 * 注入到每个页面 document-start 的 JS：
 * 1) 沉浸式取色探针：采样页面顶部/主题色，经 console 上报给原生（__TTW_CHROME__）
 *    参考实现：aira-browser HostedWebNode 页面主题探针
 * 2) TapTap 页内元素隐藏：底部"TapTap内打开"条、右上角"下载App"按钮
 */

export const WEB_CHROME_SCRIPT: string = `
;(function () {
  if (window.__ttwChromeInstalled) { return; }
  window.__ttwChromeInstalled = 1;

  /* ---------------- 取色探针 ---------------- */
  var lastBg = '';

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

  function sendTheme() {
    try {
      var bg = sampleTopBackground();
      if (!bg || bg === lastBg) { return; }
      lastBg = bg;
      console.info('__TTW_CHROME__' + JSON.stringify({ bg: bg }));
    } catch (e) { }
  }

  var themeTimer = null;
  function scheduleTheme() {
    if (themeTimer) { return; }
    themeTimer = setTimeout(function () { themeTimer = null; sendTheme(); }, 300);
  }

  /* ---------------- TapTap 元素隐藏 ---------------- */
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
        if (text.indexOf('TapTap内打开') >= 0 || text.indexOf('打开TapTap') >= 0 ||
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
    try {
      new MutationObserver(scheduleHide).observe(document.body, { childList: true, subtree: true });
    } catch (e) { }
  }

  if (document.body) {
    installBodyObservers();
  } else {
    document.addEventListener('DOMContentLoaded', function () {
      installBodyObservers();
      scheduleTheme();
      scheduleHide();
    }, { once: true });
  }

  window.addEventListener('load', function () { scheduleTheme(); scheduleHide(); });
  window.addEventListener('pageshow', function () { scheduleTheme(); scheduleHide(); });
  setInterval(scheduleTheme, 2000);
  setInterval(hideTaptapPromos, 1500);
  scheduleTheme();
  scheduleHide();
})();
//# sourceURL=ttw-web-chrome.js
`;
