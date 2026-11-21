/* Wijaya landing page — i18n (YAML) + theme toggle + copy buttons.
   Tanpa dependensi eksternal. Struktur YAML yang didukung:
   pemetaan bersarang (indentasi), `key: value`, nilai boleh dikutip. */
(function () {
  'use strict';

  var LANGS = ['id', 'en', 'ar', 'nl', 'fr', 'de', 'hi', 'it', 'ja', 'ko', 'ru', 'es', 'th', 'he', 'zh'];
  var RTL = { ar: true, he: true };
  var dict = null;

  /* ---------- parser YAML minimal ---------- */
  function unquote(s) {
    var v = s.trim();
    if (v.length >= 2) {
      var q = v.charAt(0);
      if ((q === '"' || q === "'") && v.charAt(v.length - 1) === q) {
        v = v.slice(1, -1);
        v = q === '"' ? v.replace(/\\"/g, '"').replace(/\\\\/g, '\\') : v.replace(/''/g, "'");
      }
    }
    return v;
  }

  function parseYAML(text) {
    var root = {};
    var stack = [{ indent: -1, node: root }];
    text.split(/\r?\n/).forEach(function (raw) {
      if (!raw.trim() || /^\s*#/.test(raw)) return;
      var indent = raw.match(/^\s*/)[0].length;
      var line = raw.trim();
      var i = line.indexOf(':');
      if (i === -1) return;
      var key = line.slice(0, i).trim();
      var val = line.slice(i + 1).trim();
      while (stack.length > 1 && indent <= stack[stack.length - 1].indent) stack.pop();
      var parent = stack[stack.length - 1].node;
      if (val === '') {
        var node = {};
        parent[key] = node;
        stack.push({ indent: indent, node: node });
        return;
      }
      parent[key] = unquote(val);
    });
    return root;
  }

  function pick(path) {
    if (!dict) return null;
    var cur = dict;
    var parts = path.split('.');
    for (var i = 0; i < parts.length; i++) {
      if (cur == null || typeof cur !== 'object') return null;
      cur = cur[parts[i]];
    }
    return typeof cur === 'string' ? cur : null;
  }

  /* ---------- terapkan terjemahan ---------- */
  function apply(newDict) {
    dict = newDict;
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var v = pick(el.getAttribute('data-i18n'));
      if (v != null) el.innerHTML = v;
    });
    document.querySelectorAll('[data-i18n-alt]').forEach(function (el) {
      var v = pick(el.getAttribute('data-i18n-alt'));
      if (v != null) el.setAttribute('alt', v);
    });
    var title = pick('meta.title');
    if (title) document.title = title;
    var desc = pick('meta.description');
    if (desc) {
      var m = document.querySelector('meta[name="description"]');
      if (m) m.setAttribute('content', desc);
      var og = document.querySelector('meta[property="og:title"]');
      if (og && title) og.setAttribute('content', title);
    }
    updateThemeLabel();
  }

  /* ---------- tema ---------- */
  function isLight() { return document.documentElement.getAttribute('data-theme') === 'light'; }

  function updateThemeLabel() {
    var btn = document.getElementById('theme');
    if (!btn) return;
    var label = pick(isLight() ? 'ui.to_dark' : 'ui.to_light');
    if (label) { btn.setAttribute('title', label); btn.setAttribute('aria-label', label); }
  }

  function setTheme(mode) {
    document.documentElement.setAttribute('data-theme', mode);
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', mode === 'light' ? '#F8FAFC' : '#0F172A');
    var sun = document.getElementById('icon-sun');
    var moon = document.getElementById('icon-moon');
    if (sun && moon) { sun.hidden = (mode !== 'light'); moon.hidden = (mode === 'light'); }
    var btn = document.getElementById('theme');
    if (btn) btn.setAttribute('aria-pressed', mode === 'light' ? 'true' : 'false');
    updateThemeLabel();
  }

  /* ---------- bahasa ---------- */
  function setLang(code) {
    document.documentElement.lang = code;
    document.documentElement.dir = RTL[code] ? 'rtl' : 'ltr';
    fetch('i18n/' + code + '.yml', { cache: 'no-cache' })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(function (txt) { apply(parseYAML(txt)); })
      .catch(function () { /* biarkan teks fallback di HTML */ });
  }

  function initLang() {
    var stored = null;
    try { stored = localStorage.getItem('wijaya.lang'); } catch (e) {}
    var code = stored;
    if (!code) {
      var nav = (navigator.language || 'en').slice(0, 2).toLowerCase();
      code = LANGS.indexOf(nav) >= 0 ? nav : 'en';
    }
    var sel = document.getElementById('lang');
    if (sel) {
      sel.value = code;
      sel.addEventListener('change', function () {
        try { localStorage.setItem('wijaya.lang', this.value); } catch (e) {}
        setLang(this.value);
      });
    }
    if (code !== 'id') setLang(code); else apply(parseYAML(FALLBACK_ID));
  }

  /* ---------- tombol salin ---------- */
  function initCopy() {
    document.querySelectorAll('[data-copy]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        var text = btn.getAttribute('data-copy');
        var done = function () {
          var copied = pick('ui.copied') || 'Tersalin';
          btn.textContent = copied;
          setTimeout(function () {
            var back = pick('ui.copy');
            btn.textContent = back != null ? back : 'Copy';
          }, 1400);
        };
        if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, done);
        else done();
      });
    });
  }

  /* fallback bahasa Indonesia bila berkas id.yml belum sempat dimuat */
  var FALLBACK_ID = '';

  function init() {
    var t = null;
    try { t = localStorage.getItem('wijaya.theme'); } catch (e) {}
    if (!t) t = (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) ? 'light' : 'dark';
    setTheme(t);
    var btn = document.getElementById('theme');
    if (btn) btn.addEventListener('click', function () {
      var next = isLight() ? 'dark' : 'light';
      try { localStorage.setItem('wijaya.theme', next); } catch (e) {}
      setTheme(next);
    });
    initCopy();
    initLang();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
