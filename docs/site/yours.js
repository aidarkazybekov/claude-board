// "What would Pitwall find on your Mac?" Reads ~/.claude/projects in this tab, with the same
// counting rules as the app (Sources/Pitwall/Ingest/PromptText.swift, TranscriptParser.swift).
// No network: the files are streamed from disk into this script and only the totals are kept.
(function (root) {
  'use strict';

  // ---------- Counting rules, ported from the app ----------
  var PLUMBING = ['/clear', '/compact', '/model', '/mcp', '/login', '/logout', '/exit', '/quit', '/resume', '/config',
    '/cost', '/help', '/status', '/context', '/plugins', '/plugin', '/permissions', '/memory', '/doctor',
    '/init', '/hooks', '/agents', '/ide', '/terminal-setup', '/vim', '/theme', '/fast', '/usage',
    '/add-dir', '/bug', '/release-notes', '/upgrade', '/statusline', '/output-style', '/export', '/rewind'];
  var SKIP_PREFIX = ['<bash-', '<local-command', 'Caveat:', 'This session is being continued', '<task-notification',
    '<artifact-', '<side-sessions-event', '<ci-monitor-event'];
  var REPLY_WORDS = ['y', 'yes', 'yeah', 'yep', 'yup', 'no', 'nope', 'ok', 'okay', 'k', 'sure', 'go', 'go ahead', 'continue',
    'proceed', 'do it', 'start', 'next', 'done', 'thanks', 'thank you', 'thx', 'lgtm', 'approve', 'approved',
    'agree', 'agreed', 'fine', 'good', 'great', 'perfect', 'nice', 'cool', 'both', 'all', 'all of them',
    'keep going', 'go on', 'carry on', 'ship it', 'merge', 'commit', 'push', 'retry', 'try again', 'again',
    'да', 'нет', 'ок', 'окей', 'давай', 'продолжай', 'продолжи', 'согласен', 'хорошо', 'отлично', 'го',
    'делай', 'сделай', 'запускай', 'спасибо', 'ага', 'угу', 'верно', 'правильно', 'вперед', 'вперёд', 'дальше',
    'супер', 'класс', 'норм', 'можно', 'начинай', 'поехали', 'оба', 'все', 'всё'];
  var REPLY_PREFIX = ['yes ', 'yes,', 'yeah ', 'ok ', 'ok,', 'okay ', 'okay,', 'no ', 'no,', 'sure ', 'go ahead', 'do it',
    "let's go", 'lets go', 'continue ', 'proceed ', 'option ', 'да ', 'да,', 'нет ', 'нет,', 'давай ', 'давай,',
    'ок ', 'ок,', 'хорошо ', 'хорошо,', 'продолжай', 'согласен', 'вариант '];
  var TRIVIAL = ['hi', 'hello', 'hey', 'test', 'ping', 'привет', 'тест', 'yo', 'sup', 'exit', 'clear', 'quit', 'mcp',
    'where', 'help', 'status', 'resume', 'login', 'logout'];
  var EDGE = /^[\s\p{P}]+|[\s\p{P}]+$/gu;

  function between(s, a, b) { var i = s.indexOf(a); if (i < 0) return null; i += a.length; var j = s.indexOf(b, i); return j < 0 ? null : s.slice(i, j); }

  function clean(raw) {
    var text = raw;
    for (var i = 0; i < SKIP_PREFIX.length; i++) if (text.indexOf(SKIP_PREFIX[i]) === 0) return null;
    if (text.indexOf('<command-name>') >= 0) {
      var name = (between(text, '<command-name>', '</command-name>') || '').trim();
      var args = (between(text, '<command-args>', '</command-args>') || '').trim();
      if (!args || PLUMBING.indexOf(name) >= 0) return null;
      text = name + ' ' + args;
    }
    text = text.split('[Request interrupted by user for tool use]').join('').split('[Request interrupted by user]').join('').trim();
    if (!text || text[0] === '!') return null;
    if (text[0] === '/' && PLUMBING.indexOf(text.split(/[\s]/)[0].toLowerCase()) >= 0) return null;
    return text;
  }
  function norm(text) { return text.toLowerCase().replace(EDGE, ''); }
  function isFollowUp(text, asked) {
    var t = norm(text), n = Array.from(t).length;
    if (n <= 3 || REPLY_WORDS.indexOf(t) >= 0 || /^[\d,. ]+$/.test(t)) return true;
    var oneLine = text.indexOf('\n') < 0;
    if (oneLine && n < 40) return true;
    if (oneLine && n < 70 && REPLY_PREFIX.some(function (p) { return t.indexOf(p) === 0; })) return true;
    return asked && oneLine && n < 60;
  }
  function isTrivial(text) { var t = norm(text); return Array.from(t).length < 3 || TRIVIAL.indexOf(t) >= 0; }

  function assistantAsked(raw) {
    if (!raw) return false;
    if (raw.indexOf('"name":"AskUserQuestion"') >= 0) return true;
    try {
      var o = JSON.parse(raw), parts = (o.message && o.message.content) || [], text = '';
      if (typeof parts === 'string') text = parts;
      else for (var i = 0; i < parts.length; i++) if (parts[i].type === 'text') text += (text ? '\n' : '') + (parts[i].text || '');
      text = text.trim();
      return /\?$/.test(text) || text.slice(-200).indexOf('?\n') >= 0;
    } catch (e) { return false; }
  }
  function dayKey(ms) { var d = new Date(ms); return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate(); }
  // Project from a working folder, like the app's ProjectResolver with its default roots: worktrees fold
  // into their repo, and a folder under ~/DEV, ~/Developer, ~/code… is the first folder below that root.
  var ROOTS = ['Documents/GitHub', 'Documents/Projects', 'DEV', 'Developer', 'Projects', 'projects', 'code', 'Code', 'src', 'dev',
    'workspace', 'Workspace', 'repos', 'git', 'GitHub', 'Sites'];
  function projectOf(cwd) {
    if (!cwd) return null;
    var p = String(cwd).replace(/\/+$/, '');
    ['/.claude/worktrees/', '/.worktrees/', '/.claude-worktrees/'].forEach(function (m) { var i = p.indexOf(m); if (i >= 0) p = p.slice(0, i); });
    if (p.indexOf('/Application Support/Claude/scratch-workspaces') >= 0) return RU_SCRATCH ? 'Черновики' : 'Scratch';
    var parts = p.split('/'), home = (parts[1] === 'Users' || parts[1] === 'home') ? 3 : 0;
    if (home) {
      var rel = parts.slice(home);
      for (var i = 0; i < ROOTS.length; i++) {
        var r = ROOTS[i].split('/');
        if (r.every(function (x, j) { return rel[j] === x; })) return rel[r.length] || r[r.length - 1];
      }
    }
    return parts[parts.length - 1] || p;
  }
  var RU_SCRATCH = typeof document !== 'undefined' && document.documentElement.lang === 'ru';

  // ---------- Analyzer: feed it files as text chunks ----------
  function Analyzer(now) {
    this.now = now || Date.now();
    this.requests = 0; this.replies = 0; this.sessions = 0; this.waiting = 0;
    this.first = 0; this.projects = {}; this.days = {}; this.hours = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
  }
  Analyzer.prototype.begin = function () {
    this.f = { parts: [], cwd: null, has: false, lastAsst: null, lastKind: null, lastTs: 0 };
  };
  Analyzer.prototype.push = function (chunk) {
    var f = this.f;
    // A line can span many chunks (big tool outputs): park pieces until a newline arrives, so a long
    // line is scanned once instead of once per chunk.
    if (chunk.indexOf('\n') < 0) { f.parts.push(chunk); return; }
    var s = (f.parts.length ? f.parts.join('') : '') + chunk, start = 0, nl;
    f.parts = [];
    while ((nl = s.indexOf('\n', start)) >= 0) { this.line(s.slice(start, nl)); start = nl + 1; }
    f.parts.push(s.slice(start));
  };
  Analyzer.prototype.end = function () {
    var f = this.f;
    var rest = f.parts.join(''); if (rest) this.line(rest);
    if (f.has) {
      this.sessions++;
      var recent = f.lastTs && this.now - f.lastTs < 14 * 864e5;
      if (recent && f.lastKind === 'asst' && assistantAsked(f.lastAsst)) this.waiting++;
    }
    this.f = null;
  };
  Analyzer.prototype.line = function (line) {
    if (line.length < 20 || line.indexOf('"isSidechain":true') >= 0) return;
    var f = this.f;
    if (line.indexOf('"type":"assistant"') >= 0) {
      f.lastAsst = line; f.lastKind = 'asst';
      var m = /"timestamp":"([^"]+)"/.exec(line); if (m) f.lastTs = Date.parse(m[1]) || f.lastTs;
      return;
    }
    if (line.indexOf('"type":"user"') < 0) return;
    if (line.indexOf('"tool_use_id"') >= 0) { f.lastKind = 'tool'; return; }
    if (line.indexOf('"isMeta":true') >= 0 || line.indexOf('"isCompactSummary":true') >= 0) return;
    var o; try { o = JSON.parse(line); } catch (e) { return; }
    if (o.type !== 'user' || !o.message) return;
    var origin = o.origin && o.origin.kind, c = o.message.content, raw = '';
    if (typeof c === 'string') { if (!origin && c[0] === '<') return; raw = c; }
    else if (Array.isArray(c)) {
      for (var i = 0; i < c.length; i++) {
        if (c[i].type === 'tool_result') return;
        if (c[i].type === 'text') raw += (raw ? '\n' : '') + (c[i].text || '');
      }
    }
    if (origin && origin !== 'human') return;
    if (o.cwd && !f.cwd) f.cwd = o.cwd;
    var text = clean(raw); if (text === null) return;
    var ts = Date.parse(o.timestamp) || f.lastTs || this.now;
    f.lastKind = 'user'; f.lastTs = ts;
    if (f.has && (isFollowUp(text, assistantAsked(f.lastAsst)) || isTrivial(text))) { this.replies++; return; }
    if (!f.has && isTrivial(text)) return;
    f.has = true;
    this.requests++;
    var p = projectOf(o.cwd || f.cwd) || '?';
    this.projects[p] = (this.projects[p] || 0) + 1;
    var k = dayKey(ts); this.days[k] = (this.days[k] || 0) + 1;
    this.hours[new Date(ts).getHours()]++;
    if (!this.first || ts < this.first) this.first = ts;
  };
  Analyzer.prototype.result = function () {
    var keys = Object.keys(this.days).map(Number).sort(function (a, b) { return a - b; });
    var streak = 0, run = 0, prev = null, busiest = null;
    keys.forEach(function (k) {
      var d = Date.UTC(Math.floor(k / 10000), Math.floor(k / 100) % 100 - 1, k % 100) / 864e5;
      run = prev !== null && d - prev === 1 ? run + 1 : 1; prev = d; if (run > streak) streak = run;
    }, this);
    var days = this.days;
    keys.forEach(function (k) { if (busiest === null || days[k] > days[busiest]) busiest = k; });
    var hour = this.hours.indexOf(Math.max.apply(null, this.hours));
    var projects = this.projects;
    var top = Object.keys(projects).sort(function (a, b) { return projects[b] - projects[a] || a.localeCompare(b); }).slice(0, 5)
      .map(function (n) { return { name: n, count: projects[n] }; });
    return {
      requests: this.requests, replies: this.replies, sessions: this.sessions, waiting: this.waiting,
      projects: Object.keys(projects).length, first: this.first, activeDays: keys.length, streak: streak,
      busiest: busiest === null ? null : { day: busiest, count: days[busiest] }, hour: this.requests ? hour : null, top: top
    };
  };

  // Which files are top-level session transcripts: <...>/projects/<project>/<session>.jsonl.
  function pickTranscripts(entries) {
    var jsonl = entries.filter(function (e) {
      return /\.jsonl$/.test(e.path) && e.path.indexOf('/subagents/') < 0 && !/(^|\/)history\.jsonl$/.test(e.path);
    });
    var strict = jsonl.filter(function (e) { var p = e.path.split('/'); return p.length >= 3 && p[p.length - 3] === 'projects'; });
    return strict.length ? strict : jsonl;
  }

  var core = { Analyzer: Analyzer, projectOf: projectOf, clean: clean, isFollowUp: isFollowUp, isTrivial: isTrivial, pickTranscripts: pickTranscripts };
  if (typeof module !== 'undefined' && module.exports) module.exports = core;
  if (typeof document === 'undefined') return;

  // ---------- The widget ----------
  var el = document.getElementById('yours');
  if (!el) return;
  var RU = document.documentElement.lang === 'ru';
  var S = RU ? {
    reading: 'Читаю {n} из {total} транскриптов', none: 'В этой папке нет транскриптов Claude Code. Выберите ~/.claude/projects.',
    failed: 'Не удалось прочитать папку. Попробуйте ещё раз или выберите ~/.claude/projects.',
    since: 'запросов к Claude с {date}', sinceNone: 'запросов к Claude',
    sessions: { one: 'сессия', few: 'сессии', many: 'сессий', other: 'сессии' }, projects: { one: 'проект', few: 'проекта', many: 'проектов', other: 'проекта' },
    active: { one: 'день с Claude', few: 'дня с Claude', many: 'дней с Claude', other: 'дня с Claude' }, streak: 'рекорд подряд', busiest: 'самый загруженный день', hour: 'обычное время',
    days: { one: '{n} день', few: '{n} дня', many: '{n} дней', other: '{n} дня' }, busiestV: '{n} запр.',
    wait: { one: '{n} недавняя сессия закончилась вопросом от Claude.', few: '{n} недавние сессии закончились вопросом от Claude.',
      many: '{n} недавних сессий закончились вопросом от Claude.', other: '{n} недавней сессии закончились вопросом от Claude.' },
    waitSub: 'Pitwall собирает такие в «Ждут вас», чтобы ни одна не потерялась.',
    top: 'Куда ушла основная работа', req: 'запр.',
    replies: 'Плюс {n} коротких ответов вроде «да» и «давай»: приложение относит их к запросу, на который они отвечают.',
    copied: 'Скопировано', press: 'Нажмите ⌘C',
    share: 'Я дал Claude Code {n} запросов в {p} проектах с {date}. Рекорд: {s} подряд. Посчитано в браузере с Pitwall: https://aidarkazybekov.github.io/pitwall/ru/'
  } : {
    reading: 'Reading {n} of {total} transcripts', none: 'No Claude Code transcripts in that folder. Choose ~/.claude/projects.',
    failed: "Couldn't read that folder. Try again, or choose ~/.claude/projects.",
    since: "requests you've given Claude since {date}", sinceNone: "requests you've given Claude",
    sessions: { one: 'session', other: 'sessions' }, projects: { one: 'project', other: 'projects' }, active: { one: 'day with Claude', other: 'days with Claude' }, streak: 'best streak', busiest: 'busiest day', hour: 'usual hour',
    days: { one: '{n} day', other: '{n} days' }, busiestV: '{n} requests',
    wait: { one: '{n} recent session ended with Claude asking you something.', other: '{n} recent sessions ended with Claude asking you something.' },
    waitSub: 'Pitwall gathers those in Needs You, so none of them gets lost.',
    top: 'Where most of your work went', req: 'requests',
    replies: 'Plus {n} short replies like "yes" and "go ahead": the app folds those into the request they answer.',
    copied: 'Copied', press: 'Press ⌘C',
    share: "I've given Claude Code {n} requests across {p} projects since {date}. Best streak: {s} in a row. Counted in my browser with Pitwall: https://aidarkazybekov.github.io/pitwall/"
  };
  var locale = RU ? 'ru-RU' : 'en-US';
  var num = new Intl.NumberFormat(locale);
  var fmtDate = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'long', year: 'numeric' });
  var fmtDay = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short' });
  var fmtHour = new Intl.DateTimeFormat(locale, { hour: 'numeric', minute: '2-digit' });
  var plural = new Intl.PluralRules(locale);
  function pl(forms, n) { return forms[plural.select(n)] || forms.other; }
  function days(n) { return F(pl(S.days, n), { n: num.format(n) }); }
  function F(s, v) { return s.replace(/\{(\w+)\}/g, function (_, k) { return v[k]; }); }
  function esc(t) { return String(t).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }

  var input = document.getElementById('yours-input');
  var card = document.getElementById('yours-card');
  var out = document.getElementById('yours-result');
  var status = document.getElementById('yours-status');
  var bar = document.getElementById('yours-bar');
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var busy = false, lastShare = '';

  function state(s) { card.dataset.state = s; }
  function fail(msg) { busy = false; state('idle'); status.textContent = msg; status.classList.add('err'); }

  function read(entries) {
    if (busy) return;
    var files = pickTranscripts(entries);
    status.classList.remove('err');
    if (!files.length) { fail(S.none); return; }
    busy = true; state('reading');
    var a = new Analyzer(), total = files.reduce(function (s, e) { return s + e.file.size; }, 0), done = 0, i = 0, shown = 0;
    function progress() { bar.style.transform = 'scaleX(' + (total ? done / total : 1) + ')'; status.textContent = F(S.reading, { n: num.format(Math.min(i + 1, files.length)), total: num.format(files.length) }); }
    function next() {
      if (i >= files.length) { busy = false; show(a.result()); return; }
      var file = files[i].file;
      a.begin();
      var finish = function () { a.end(); i++; next(); };
      if (file.stream && window.TextDecoderStream) {
        var reader = file.stream().pipeThrough(new TextDecoderStream()).getReader();
        (function pump() {
          reader.read().then(function (r) {
            if (r.done) { finish(); return; }
            a.push(r.value); done += r.value.length;
            var now = performance.now(); if (now - shown > 80) { shown = now; progress(); }
            pump();
          }, function () { finish(); });
        })();
      } else {
        file.text().then(function (t) { a.push(t); done += file.size; progress(); finish(); }, finish);
      }
    }
    progress(); next();
  }

  function show(r) {
    if (!r.requests) { fail(S.none); return; }
    status.textContent = '';
    var tiles = [
      [r.sessions, pl(S.sessions, r.sessions)], [r.projects, pl(S.projects, r.projects)], [r.activeDays, pl(S.active, r.activeDays)], [days(r.streak), S.streak],
      [r.busiest ? fmtDay.format(dateOf(r.busiest.day)) : '–', S.busiest + (r.busiest ? ' · ' + F(S.busiestV, { n: num.format(r.busiest.count) }) : '')],
      [r.hour === null ? '–' : fmtHour.format(new Date(2000, 0, 1, r.hour)), S.hour]
    ];
    out.innerHTML =
      '<p class="y-big"><span class="y-num" data-to="' + r.requests + '">' + num.format(r.requests) + '</span></p>' +
      '<p class="y-since">' + esc(r.first ? F(S.since, { date: fmtDate.format(new Date(r.first)) }) : S.sinceNone) + '</p>' +
      '<div class="y-tiles">' + tiles.map(function (t) {
        return '<div><b>' + esc(typeof t[0] === 'number' ? num.format(t[0]) : t[0]) + '</b><span>' + esc(t[1]) + '</span></div>';
      }).join('') + '</div>' +
      (r.waiting ? '<div class="y-wait"><strong>' + esc(F(pl(S.wait, r.waiting), { n: num.format(r.waiting) })) + '</strong><span>' + esc(S.waitSub) + '</span></div>' : '') +
      '<div class="y-top"><h4>' + esc(S.top) + '</h4><ol>' + r.top.map(function (p) {
        return '<li><span>' + esc(p.name) + '</span><span>' + num.format(p.count) + ' ' + esc(S.req) + '</span></li>';
      }).join('') + '</ol></div>' +
      (r.replies ? '<p class="y-note">' + esc(F(S.replies, { n: num.format(r.replies) })) + '</p>' : '');
    lastShare = F(S.share, { n: num.format(r.requests), p: num.format(r.projects), date: r.first ? fmtDate.format(new Date(r.first)) : '?', s: days(r.streak) });
    state('done');
    count(out.querySelector('.y-num'));
    card.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'nearest' });
  }
  function dateOf(k) { return new Date(Math.floor(k / 10000), Math.floor(k / 100) % 100 - 1, k % 100); }
  function count(node) {
    var to = +node.dataset.to; if (reduce || to < 10) return;
    var t0 = performance.now(), dur = 1400;
    (function tick(t) {
      var p = Math.min(1, (t - t0) / dur), e = 1 - Math.pow(1 - p, 3);
      node.textContent = num.format(Math.round(to * e));
      if (p < 1) requestAnimationFrame(tick);
    })(t0);
  }

  // Folder picker.
  document.getElementById('yours-pick').addEventListener('click', function () { if (!busy) input.click(); });
  input.addEventListener('change', function () {
    var list = Array.prototype.map.call(input.files || [], function (f) { return { file: f, path: f.webkitRelativePath || f.name }; });
    read(list);
  });

  // Drag and drop a folder (or files).
  function walk(entry, path, acc) {
    return new Promise(function (resolve) {
      if (entry.isFile) { entry.file(function (f) { acc.push({ file: f, path: path + entry.name }); resolve(); }, function () { resolve(); }); return; }
      if (!entry.isDirectory) { resolve(); return; }
      if (entry.name === 'subagents') { resolve(); return; }
      var reader = entry.createReader(), kids = [];
      (function more() {
        reader.readEntries(function (batch) {
          if (!batch.length) { Promise.all(kids.map(function (k) { return walk(k, path + entry.name + '/', acc); })).then(function () { resolve(); }); return; }
          kids = kids.concat(Array.prototype.slice.call(batch)); more();
        }, function () { resolve(); });
      })();
    });
  }
  ['dragenter', 'dragover'].forEach(function (t) { card.addEventListener(t, function (e) { e.preventDefault(); if (!busy) card.classList.add('over'); }); });
  ['dragleave', 'drop'].forEach(function (t) { card.addEventListener(t, function () { card.classList.remove('over'); }); });
  card.addEventListener('drop', function (e) {
    e.preventDefault();
    var items = e.dataTransfer && e.dataTransfer.items;
    if (items && items.length && items[0].webkitGetAsEntry) {
      var acc = [], roots = Array.prototype.map.call(items, function (it) { return it.webkitGetAsEntry(); }).filter(Boolean);
      Promise.all(roots.map(function (r) { return walk(r, '', acc); })).then(function () { read(acc); }, function () { fail(S.failed); });
    } else if (e.dataTransfer && e.dataTransfer.files) {
      read(Array.prototype.map.call(e.dataTransfer.files, function (f) { return { file: f, path: f.name }; }));
    }
  });

  // Copy helpers: the folder path, and the shareable summary (no project names).
  function copy(btn, text, ok, select) {
    function label(t) { var orig = btn.dataset.label || btn.textContent; btn.dataset.label = orig; btn.textContent = t; setTimeout(function () { btn.textContent = orig; }, 2000); }
    function fallback() {
      var ta = document.createElement('textarea'); ta.value = text; ta.setAttribute('readonly', ''); ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta); ta.select(); var done = false; try { done = document.execCommand('copy'); } catch (e) { done = false; }
      document.body.removeChild(ta);
      if (!done && select) select();  // leave the text selected so ⌘C works
      label(done ? ok : S.press);
    }
    if (navigator.clipboard && window.isSecureContext) navigator.clipboard.writeText(text).then(function () { label(ok); }, fallback); else fallback();
  }
  function selectNode(n) { if (!n) return; var r = document.createRange(); r.selectNodeContents(n); var s = getSelection(); s.removeAllRanges(); s.addRange(r); }
  el.addEventListener('click', function (e) {
    var b = e.target.closest('[data-yours]'); if (!b) return;
    var what = b.dataset.yours;
    if (what === 'path') copy(b, '~/.claude/projects', S.copied, function () { selectNode(el.querySelector('.yours-steps code')); });
    if (what === 'share' && lastShare) copy(b, lastShare, S.copied, function () {
      var box = card.querySelector('.y-share');
      if (!box) { box = document.createElement('textarea'); box.className = 'y-share'; box.readOnly = true; box.rows = 3; card.querySelector('.y-actions').after(box); }
      box.value = lastShare; box.focus(); box.select();
    });
    if (what === 'clear') { var sb = card.querySelector('.y-share'); if (sb) sb.remove(); out.innerHTML = ''; lastShare = ''; input.value = ''; status.textContent = ''; status.classList.remove('err'); state('idle'); }
  });
})(this);
