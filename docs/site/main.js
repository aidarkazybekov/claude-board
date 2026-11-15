  // Interactive mini board: drag cards, open details, and a scripted "live" moment when it scrolls into view.
  (function () {
    var board = document.getElementById('mini-board');
    if (!board) return;
    var drawer = document.getElementById('mini-drawer');
    var mini = document.getElementById('mini');
    var T = function (k, d) { return (mini && mini.dataset[k]) || d; };
    var live = document.getElementById('mini-live');
    var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var COLS = [['todo', 'To Do', 'var(--todo)'], ['prog', 'In Progress', 'var(--prog)'], ['needs', 'Needs You', 'var(--needs)'], ['done', 'Done', 'var(--done)']];
    var PC = { web: '#4078f2', api: '#945ce6', billing: '#e6548c', mobile: '#21a3a3', infra: '#f28c33', 'recipe-bot': '#4da854' };
    function fresh() {
      return [
        { id: 'WEB-2', title: 'Checkout redesign: one column on mobile', project: 'web', status: 'prog', busy: true, link: 'T-004',
          request: 'Work on T-004: redesign the checkout. One column on mobile, order summary in a sidebar on desktop.',
          steps: [['Audit current components', 1], ['Build the responsive layout', 1], ['Move order summary to a sidebar', 0], ['Update Playwright tests', 0]] },
        { id: 'API-2', title: 'Shared rate-limit store across instances', project: 'api', status: 'prog', busy: true, link: 'T-006',
          request: 'The limiter state lives in memory, so it breaks with 3 instances. Look at T-006 and propose a fix.',
          steps: [['Read the current limiter', 1], ['Compare Redis with sticky sessions', 0]] },
        { id: 'BIL-1', title: 'Stripe webhooks fail after retries', project: 'billing', status: 'needs',
          ask: 'Reproduce with the Stripe CLI first, or patch the handler now?',
          request: 'Investigate the failed Stripe webhooks from last weekend (T-002).' },
        { id: 'WEB-7', title: 'Faster product images (AVIF, lazy loading)', project: 'web', status: 'todo', mine: true,
          request: 'Your task, planned before Claude knows about it.', steps: [['AVIF in the image CDN', 0], ['Lazy loading below the fold', 0]] },
        { id: 'RB-1', title: 'Add Spanish recipes to the catalogue', project: 'recipe-bot', status: 'todo', mine: true,
          request: 'Start with 30 dishes. Keep the same JSON schema.', steps: [['Pick 30 recipes', 0], ['Translate titles', 0], ['Add photos', 0]] },
        { id: 'INF-1', title: 'Cut staging costs by half', project: 'infra', status: 'done',
          request: 'Staging costs doubled last month. Find out why and cut it.', recap: 'Removed two idle GPU nodes and scaled staging to zero at night: about 55% cheaper.' },
        { id: 'MOB-1', title: 'Push opt-in after the first order', project: 'mobile', status: 'done',
          request: 'Add a push-notification opt-in screen after the first order.', recap: 'Opt-in screen after the first order, plus analytics events.' }
      ];
    }
    var tickets = fresh(), openId = null, timers = [];
    function esc(t) { return String(t).replace(/[&<>"]/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]; }); }
    function find(id) { return tickets.filter(function (t) { return t.id === id; })[0]; }
    function progress(t) { if (!t.steps) return ''; var d = t.steps.filter(function (s) { return s[1]; }).length; return d + '/' + t.steps.length; }

    function render(effects) {
      effects = effects || {};
      board.innerHTML = COLS.map(function (c) {
        var list = tickets.filter(function (t) { return t.status === c[0]; });
        return '<section class="col" data-status="' + c[0] + '" style="--c:' + c[2] + '"><header><i></i>' + c[1] + ' <span>' + list.length + '</span></header><div class="cards">' +
          list.map(function (t) {
            var cls = 'tcard' + (t.id === openId ? ' sel' : '') + (effects.landed === t.id ? ' landed' : '') + (effects.flash === t.id ? ' flash' : '');
            return '<button type="button" class="' + cls + '" data-id="' + t.id + '" aria-label="' + esc(t.id + ': ' + t.title) + '">' +
              '<span class="top">' + t.id + (t.busy ? '<span class="dot busy" title="Claude is working"></span>' : '') + '</span>' +
              '<span class="t">' + esc(t.title) + '</span>' +
              (t.status === 'needs' && t.ask ? '<span class="ask">' + esc(t.ask) + '</span>' : '') +
              '<span class="meta"><span class="chip" style="--pc:' + PC[t.project] + '">' + t.project + '</span>' + (t.steps ? '<span>' + progress(t) + '</span>' : '') + (t.mine ? '<span>Your task</span>' : '') + '</span>' +
              '</button>';
          }).join('') + '</div></section>';
      }).join('');
      var needs = tickets.filter(function (t) { return t.status === 'needs'; }).length;
      var cn = document.getElementById('cnt-needs');
      if (cn && cn.textContent !== String(needs)) { cn.textContent = needs; cn.classList.add('bump'); setTimeout(function () { cn.classList.remove('bump'); }, 1600); }
      var cp = document.getElementById('cnt-prog'); if (cp) cp.textContent = tickets.filter(function (t) { return t.status === 'prog'; }).length;
      var run = document.getElementById('run-list');
      var busy = tickets.filter(function (t) { return t.busy; }).length;
      if (run) run.textContent = busy === 0 ? T('runNone', 'Nothing running') : (busy === 1 ? T('runOne', '1 session busy') : T('runMany', '{n} sessions busy').replace('{n}', busy));
      if (openId) renderDrawer();
    }

    function renderDrawer() {
      var t = find(openId); if (!t) return;
      var col = COLS.filter(function (c) { return c[0] === t.status; })[0];
      drawer.innerHTML = '<button type="button" class="x" data-close>Close</button>' +
        '<div class="k">' + t.id + (t.link ? '  linked to ' + t.link : '') + '</div><h5>' + esc(t.title) + '</h5>' +
        '<span class="chip" style="--pc:' + PC[t.project] + '">' + t.project + '</span> <span class="chip" style="--pc:' + col[2] + '">' + col[1] + '</span>' +
        (t.status === 'needs' && t.ask ? '<div class="lbl">Claude is waiting on you</div><div class="box askbox"><b>Question</b>' + esc(t.ask) + '</div>' : '') +
        '<div class="lbl">' + (t.mine ? 'Task' : 'Request') + '</div><div class="box">' + esc(t.request) + '</div>' +
        (t.steps ? '<div class="lbl">Plan ' + progress(t) + '</div>' + t.steps.map(function (s, i) {
          return '<label class="step' + (s[1] ? ' ok' : '') + '"><input type="checkbox" data-step="' + i + '"' + (s[1] ? ' checked' : '') + '><span>' + esc(s[0]) + '</span></label>';
        }).join('') : '') +
        (t.recap ? '<div class="lbl">Outcome</div><div class="box">' + esc(t.recap) + '</div>' : '') +
        '<div class="lbl">Move to</div><div class="moves">' + COLS.map(function (c) {
          return '<button type="button" data-move="' + c[0] + '" aria-pressed="' + (c[0] === t.status) + '">' + c[1] + '</button>';
        }).join('') + '</div>' +
        '<p class="note">' + (t.mine ? T('noteStart', 'In the app, Start with Claude hands this task to Claude Code with its key, so the session links back here.') : T('noteResume', 'In the app, Resume reopens this session in Terminal.')) + '</p>';
      drawer.classList.add('open');
    }

    function move(id, status, why) {
      var t = find(id); if (!t || t.status === status) return;
      t.status = status; if (status !== 'prog') t.busy = false;
      live.textContent = id + ' ' + T('moved', 'moved to') + ' ' + COLS.filter(function (c) { return c[0] === status; })[0][1] + (why ? '. ' + why : '');
      render({ landed: id, flash: status === 'needs' ? id : null });
    }

    board.addEventListener('click', function (e) {
      var card = e.target.closest('.tcard'); if (!card || card.dataset.dragged) { if (card) delete card.dataset.dragged; return; }
      // Select without re-rendering the board, so the page doesn't jump under the pointer.
      openId = card.dataset.id;
      board.querySelectorAll('.tcard').forEach(function (c) { c.classList.toggle('sel', c === card); });
      renderDrawer();
    });
    drawer.addEventListener('click', function (e) {
      if (e.target.closest('[data-close]')) { openId = null; drawer.classList.remove('open'); render(); return; }
      var m = e.target.closest('[data-move]'); if (m) { move(openId, m.dataset.move); return; }
    });
    drawer.addEventListener('change', function (e) {
      var i = e.target.dataset.step; if (i === undefined) return;
      var t = find(openId); t.steps[i][1] = e.target.checked ? 1 : 0; render();
    });

    // Pointer dragging (mouse and pen; on touch, cards open the details panel with "Move to").
    var drag = null;
    board.addEventListener('pointerdown', function (e) {
      var card = e.target.closest('.tcard'); if (!card || e.pointerType === 'touch' || e.button !== 0) return;
      drag = { id: card.dataset.id, card: card, x: e.clientX, y: e.clientY, started: false };
    });
    window.addEventListener('pointermove', function (e) {
      if (!drag) return;
      if (!drag.started) {
        if (Math.abs(e.clientX - drag.x) + Math.abs(e.clientY - drag.y) < 6) return;
        var r = drag.card.getBoundingClientRect();
        drag.dx = drag.x - r.left; drag.dy = drag.y - r.top;
        drag.ghost = drag.card.cloneNode(true); drag.ghost.classList.add('ghost'); drag.ghost.style.width = r.width + 'px';
        document.body.appendChild(drag.ghost); drag.card.classList.add('placeholder'); drag.started = true;
      }
      drag.ghost.style.left = (e.clientX - drag.dx) + 'px'; drag.ghost.style.top = (e.clientY - drag.dy) + 'px';
      var over = document.elementFromPoint(e.clientX, e.clientY); var col = over && over.closest('.col');
      board.querySelectorAll('.col').forEach(function (c) { c.classList.toggle('over', c === col); });
      drag.target = col ? col.dataset.status : null;
    });
    window.addEventListener('pointerup', function () {
      if (!drag) return;
      var d = drag; drag = null;
      if (!d.started) return;
      d.card.dataset.dragged = '1';
      if (d.ghost) d.ghost.remove();
      board.querySelectorAll('.col').forEach(function (c) { c.classList.remove('over'); });
      if (d.target) move(d.id, d.target); else render();
    });

    // The scripted "live" moment: a busy session stops to ask, and a plan step completes.
    function play() {
      timers.forEach(clearTimeout); timers = [];
      timers.push(setTimeout(function () { move('API-2', 'needs', T('asked', 'Claude asked') + ': Use Redis for the limiter, or sticky sessions?'); find('API-2').ask = 'Use Redis for the limiter, or sticky sessions?'; render({ flash: 'API-2' }); }, 2200));
      timers.push(setTimeout(function () { var t = find('WEB-2'); if (t && t.steps) { t.steps[2][1] = 1; render({ landed: 'WEB-2' }); } }, 6200));
    }
    document.getElementById('mini-replay').addEventListener('click', function () {
      tickets = fresh(); openId = null; drawer.classList.remove('open'); render(); play();
    });
    render();
    if ('IntersectionObserver' in window) {
      var seen = false;
      new IntersectionObserver(function (entries) {
        entries.forEach(function (e) { if (e.isIntersecting && !seen) { seen = true; play(); } });
      }, { threshold: 0.35 }).observe(document.getElementById('mini'));
    } else { play(); }
  })();

  // Copy the install command. Only say "Copied" when it really was.
  (function () {
    var btn = document.getElementById('copy-install');
    var text = document.getElementById('install-text');
    if (!btn || !text) return;
    var reset;
    var L = { copy: btn.dataset.copy || 'Copy', copied: btn.dataset.copied || 'Copied', press: btn.dataset.press || 'Press \u2318C' };
    function label(t) { btn.textContent = t; clearTimeout(reset); reset = setTimeout(function () { btn.textContent = L.copy; }, 2200); }
    function fallback() {
      var r = document.createRange(); r.selectNodeContents(text);
      var sel = getSelection(); sel.removeAllRanges(); sel.addRange(r);
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
      if (ok) { sel.removeAllRanges(); label(L.copied); } else { label(L.press); }
    }
    btn.addEventListener('click', function () {
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(text.textContent).then(function () { label(L.copied); }, fallback);
      } else { fallback(); }
    });
  })();

  // Reveal sections as they scroll in, and play the tour only while it is on screen.
  (function () {
    var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if ('IntersectionObserver' in window) {
      var io = new IntersectionObserver(function (entries) {
        entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
      }, { threshold: 0.12 });
      document.querySelectorAll('.reveal').forEach(function (el) { io.observe(el); });
      // Safety net: anything already on screen (anchor links like #try, restored scroll) shows at once.
      var showVisible = function () {
        document.querySelectorAll('.reveal:not(.in)').forEach(function (el) {
          var r = el.getBoundingClientRect();
          if (r.top < innerHeight && r.bottom > 0) { el.classList.add('in'); io.unobserve(el); }
        });
      };
      window.addEventListener('load', function () { requestAnimationFrame(showVisible); });
      window.addEventListener('hashchange', function () { requestAnimationFrame(showVisible); });

      var video = document.getElementById('tour-video');
      if (video && !reduce) {
        var vo = new IntersectionObserver(function (entries) {
          entries.forEach(function (e) {
            if (e.isIntersecting) { video.play().catch(function () {}); } else { video.pause(); }
          });
        }, { threshold: 0.45 });
        vo.observe(video);
      }
    } else {
      document.querySelectorAll('.reveal').forEach(function (el) { el.classList.add('in'); });
    }
  })();

  // Phones can't run a Mac app. There, every "Download for Mac" opens a sheet that sends this page
  // to the visitor's Mac instead (share sheet → AirDrop/Messages/Notes, email, or copy).
  (function () {
    var dlg = document.getElementById('handoff');
    if (!dlg || typeof dlg.showModal !== 'function') return;
    var ua = navigator.userAgent;
    var ipad = /iPad/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
    var phone = /iPhone|iPod|Android/.test(ua) || ipad || window.matchMedia('(hover: none) and (pointer: coarse)').matches;
    if (!phone) return;
    var url = location.origin + location.pathname;
    var L = { cta: dlg.dataset.cta, copied: dlg.dataset.copied, press: dlg.dataset.press };
    var share = dlg.querySelector('[data-handoff=share]');
    var mail = dlg.querySelector('[data-handoff=mail]');
    var copyBtn = dlg.querySelector('[data-handoff=copy]');
    var field = dlg.querySelector('.handoff-url');
    var title = document.title;

    mail.href = mail.getAttribute('href') + '&body=' + encodeURIComponent(url);
    if (!navigator.share) {
      // No share sheet (e.g. some Android browsers): email becomes the main action.
      share.hidden = true;
      mail.classList.replace('btn-ghost', 'btn-primary');
      dlg.querySelector('.handoff-note').hidden = true;  // AirDrop and Handoff come through the share sheet
    }
    document.querySelectorAll('a[href*="ClaudeBoard-macOS-arm64.zip"]:not([data-handoff])').forEach(function (a) {
      a.textContent = L.cta;
      a.addEventListener('click', function (e) { e.preventDefault(); open(); });
    });
    function open() { field.hidden = true; copyBtn.textContent = copyBtn.dataset.label || copyBtn.textContent; dlg.showModal(); }

    share.addEventListener('click', function () {
      navigator.share({ title: title, url: url }).then(function () { dlg.close(); }, function () {});
    });
    copyBtn.dataset.label = copyBtn.textContent;
    function showField() { field.value = url; field.hidden = false; field.focus(); field.select(); copyBtn.textContent = L.press; }
    copyBtn.addEventListener('click', function () {
      if (navigator.clipboard && window.isSecureContext) {
        navigator.clipboard.writeText(url).then(function () { copyBtn.textContent = L.copied; }, showField);
      } else { showField(); }
    });
    dlg.querySelector('[data-handoff=try]').addEventListener('click', function () { dlg.close(); });
    // Tap outside the sheet closes it.
    dlg.addEventListener('click', function (e) { if (e.target === dlg) dlg.close(); });
  })();
