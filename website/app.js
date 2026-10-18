/* Super Paste website. Every demo is drawn from one card component and one small demo history; nothing a visitor
   types or copies here is stored or sent anywhere. */
(() => {
  "use strict";
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

  // ---------- Apps and demo history ----------
  const APPS = {
    safari: { name: "Safari", hdr: "var(--h-blue)", icon: "ic-safari" },
    notes: { name: "Notes", hdr: "var(--h-notes)", icon: "ic-notes" },
    mail: { name: "Mail", hdr: "var(--h-blue)", icon: "ic-mail" },
    photos: { name: "Photos", hdr: "var(--h-red)", icon: "ic-photos" },
    finder: { name: "Finder", hdr: "var(--h-blue)", icon: "ic-finder" },
    terminal: { name: "Terminal", hdr: "var(--h-terminal)", icon: "ic-terminal" },
    meter: { name: "Digital Color Meter", hdr: "var(--h-blue)", icon: "ic-meter" },
    pages: { name: "Pages", hdr: "var(--h-orange)", icon: "ic-pages" },
    xcode: { name: "Xcode", hdr: "var(--h-blue)", icon: "ic-xcode" },
  };
  const PIN_COLORS = { red: "var(--h-red)", orange: "var(--h-orange)", yellow: "var(--h-yellow)", green: "var(--h-green)", blue: "var(--h-blue)", purple: "var(--h-purple)", pink: "var(--h-pink)", gray: "var(--h-gray)" };
  const PINBOARDS = [
    { id: "travel", name: "Travel", color: "orange" },
    { id: "work", name: "Work", color: "purple" },
    { id: "snippets", name: "Snippets", color: "green" },
  ];

  // kind: text | rich | link | image | files | color. date: today | yesterday | week | month | older.
  const ITEMS = [
    { id: "addr", kind: "text", app: "notes", when: "2 minutes ago", date: "today", device: "Studio", title: "Hotel address", pins: ["travel"], text: "Rua Garrett 73, 1200-203 Lisboa" },
    { id: "flight", kind: "text", app: "mail", when: "25 minutes ago", date: "today", device: "Studio", pins: ["travel"], text: "UA 1931 — SFO → EWR\nSeptember 12, 7:05 AM\nConfirmation: K7Q2LM\n\nUnited Airlines" },
    { id: "cabin", kind: "link", app: "safari", when: "2 hours ago", date: "today", device: "Studio", pins: ["travel"], url: "https://www.airbnb.com/rooms/48213", host: "airbnb.com", ltitle: "Cabin near Muir Woods with a view", pv: "linear-gradient(160deg, #e8c39e 0%, #c98b5a 45%, #6b3f24 100%)" },
    { id: "photo", kind: "image", app: "photos", when: "4 hours ago", date: "today", device: "Studio", w: 4032, h: 3024, img: "linear-gradient(170deg, #d9b48f 0%, #a88d8a 45%, #4f5566 100%)" },
    { id: "brand", kind: "color", app: "meter", when: "5 hours ago", date: "today", device: "Studio", pins: ["work"], hex: "#FF6B35", on: "#fff" },
    { id: "rebase", kind: "text", app: "terminal", when: "Yesterday", date: "yesterday", device: "MacBook", mono: true, pins: ["snippets"], text: "git rebase -i HEAD~3 && git push --force-with-lease origin strip" },
    { id: "deck", kind: "files", app: "finder", when: "Yesterday", date: "yesterday", device: "Studio", pins: ["work"], name: "Offsite deck v4.key", path: "~/Documents/Offsite/Offsite deck v4.key" },
    { id: "quote", kind: "rich", app: "pages", when: "3 days ago", date: "week", device: "MacBook", pins: ["work"], html: "<b>Agenda</b><br>1. Lisbon <i>logistics</i><br>2. Q4 roadmap<br>3. <u>Hiring</u> plan", rbg: "#FFFFFF" },
    { id: "repo", kind: "link", app: "safari", when: "3 days ago", date: "week", device: "MacBook", pins: ["snippets"], url: "https://github.com/udsy19/super-paste", host: "github.com", ltitle: "udsy19/super-paste: A clipboard manager for your Mac", pv: "linear-gradient(160deg, #2b3137 0%, #0d1117 100%)" },
    { id: "reply", kind: "text", app: "mail", when: "Last week", date: "month", device: "Studio", title: "Invoice reply", pins: ["work", "snippets"], text: "Thanks for the invoice. It's been approved and will be paid on the next run, within 14 days." },
    { id: "swift", kind: "text", app: "xcode", when: "Last week", date: "month", device: "MacBook", mono: true, pins: ["snippets"], text: "let query = SearchQuery(parsing: \"app:Mail type:link\")\nlet items = store.search(query, in: .all, limit: 20, offset: 0)" },
    { id: "logo", kind: "image", app: "safari", when: "2 weeks ago", date: "month", device: "Studio", w: 1200, h: 630, img: "linear-gradient(135deg, #0A7AFF 0%, #B663E0 100%)" },
  ];
  const byId = Object.fromEntries(ITEMS.map((i) => [i.id, i]));

  const KIND_LABEL = { text: "Text", rich: "Text", link: "Link", image: "Image", files: "File", color: "Color" };

  function card(item, o = {}) {
    const app = APPS[item.app];
    const pin = o.pinboard ? PINBOARDS.concat(o.extraPinboards || []).find((p) => p.id === o.pinboard) : null;
    const hdr = pin ? PIN_COLORS[pin.color] : app.hdr;
    const title = item.title && (pin || o.titles) ? item.title : KIND_LABEL[item.kind];
    const head = `<div class="card-hd" style="--hdr:${hdr}"><div class="lab"><b>${esc(title)}</b><span>${esc(item.when)}</span></div>${pin ? '<i class="pin"></i>' : `<svg class="app app-ic" viewBox="0 0 64 64" aria-hidden="true"><use href="#${app.icon}"/></svg>`}</div>`;
    let body = "", foot = "";
    switch (item.kind) {
      case "text":
        body = `<div class="card-bd text${item.mono ? " mono" : ""}">${esc(item.text)}</div>`;
        foot = `<div class="card-ft">${item.text.length} characters</div>`;
        break;
      case "rich":
        body = `<div class="card-bd text rich" style="--rbg:${item.rbg}">${item.html}</div>`;
        foot = `<div class="card-ft">${item.html.replace(/<[^>]+>/g, "").length} characters</div>`;
        break;
      case "link":
        body = `<div class="card-bd link"><div class="pv" style="--pv:${item.pv}"><div class="fav"><svg viewBox="0 0 64 64" aria-hidden="true"><use href="#${app.icon}"/></svg></div></div><div class="meta"><b>${esc(item.ltitle)}</b><span>${esc(item.host)}</span></div></div>`;
        break;
      case "image":
        body = `<div class="card-bd image" style="--img:${item.img}"><span class="pill">${item.w} × ${item.h}</span></div>`;
        break;
      case "color":
        body = `<div class="card-bd color" style="--c:${item.hex};--on:${item.on}">${item.hex}</div>`;
        break;
      case "files":
        body = `<div class="card-bd files"><svg class="ficon" viewBox="0 0 64 80" aria-hidden="true"><use href="#ic-file"/></svg><b>${esc(item.name)}</b><span>${esc(item.path)}</span></div>`;
        break;
    }
    const badge = o.number ? `<span class="badge">${o.number}</span>` : "";
    const plain = o.plain ? `<span class="plain-mark" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M4 6h16M4 12h10M4 18h14"/></svg></span>` : "";
    const label = `${title} from ${app.name}, ${item.when}`;
    return `<article class="card${o.selected ? " sel" : ""}" data-id="${item.id}" role="listitem" aria-label="${esc(label)}">${head}${body}${foot}${badge}${plain}</article>`;
  }

  // ---------- Theme ----------
  const themeBtn = $("[data-theme-toggle]");
  if (themeBtn) {
    themeBtn.addEventListener("click", () => {
      const root = document.documentElement;
      const dark = root.getAttribute("data-theme") === "dark" || (!root.getAttribute("data-theme") && matchMedia("(prefers-color-scheme: dark)").matches);
      const next = dark ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("sp-theme", next); } catch (e) {}
    });
  }

  // ---------- Copy buttons ----------
  const toast = $("[data-toast]");
  let toastTimer;
  function say(msg) {
    if (!toast) return;
    toast.textContent = msg; toast.classList.add("on");
    clearTimeout(toastTimer); toastTimer = setTimeout(() => toast.classList.remove("on"), 1600);
  }
  $$("[data-copy]").forEach((b) => b.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(b.getAttribute("data-copy")); say("Copied"); }
    catch (e) { say("Select and copy it by hand"); }
  }));

  // ---------- Reveal + nav highlight ----------
  const io = new IntersectionObserver((es) => es.forEach((e) => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } }), { rootMargin: "0px 0px -8% 0px" });
  $$(".reveal").forEach((el) => io.observe(el));

  const navLinks = $$("[data-nav] a");
  const sections = navLinks.map((a) => $(a.getAttribute("href"))).filter(Boolean);
  const navIO = new IntersectionObserver((es) => {
    es.forEach((e) => { if (e.isIntersecting) {
      navLinks.forEach((a) => a.removeAttribute("aria-current"));
      const a = navLinks.find((l) => l.getAttribute("href") === "#" + e.target.id);
      if (a) { a.setAttribute("aria-current", "true"); a.scrollIntoView({ block: "nearest", inline: "center", behavior: reduced ? "auto" : "smooth" }); }
    } });
  }, { rootMargin: "-40% 0px -55% 0px" });
  sections.forEach((s) => navIO.observe(s));

  // A demo runs only while on screen.
  function whenVisible(el, start, stop) {
    if (!el) return;
    const o = new IntersectionObserver((es) => es.forEach((e) => (e.isIntersecting ? start() : stop && stop())), { threshold: 0.25 });
    o.observe(el);
  }

  // ---------- Hero scene ----------
  (function scene() {
    const root = $("[data-scene]");
    if (!root) return;
    const strip = $("[data-strip]", root), cardsEl = $("[data-scene-cards]", root), pointer = $("[data-pointer]", root);
    const notes = $('[data-win="notes"]', root), mail = $('[data-win="mail"]', root), sel = $("[data-sel]", root);
    const ins1 = $("[data-ins-1]", root), ins2 = $("[data-ins-2]", root), hud = $("[data-hud]", root), mbApp = $("[data-mb-app]", root), mbSp = $("[data-mb-sp]", root);
    const keys = Object.fromEntries($$("[data-key]", root).map((k) => [k.dataset.key, k]));
    const stepBtns = $$("[data-step]");
    const base = ["flight", "cabin", "photo", "brand", "rebase", "deck"];
    let timers = [], running = false, stepIndex = 0;

    function render(ids, selected) {
      cardsEl.innerHTML = ids.map((id) => card(byId[id], { selected: id === selected })).join("");
    }
    function front(which) {
      notes.classList.toggle("front", which === "notes"); notes.classList.toggle("back", which !== "notes");
      mail.classList.toggle("front", which === "mail"); mail.classList.toggle("back", which !== "mail");
      mbApp.textContent = which === "notes" ? "Notes" : "Mail";
      if (which === "notes") notes.style.zIndex = 3, mail.style.zIndex = 2; else notes.style.zIndex = 2, mail.style.zIndex = 3;
    }
    function key(name, on) { Object.values(keys).forEach((k) => k.classList.remove("on")); if (name && on !== false) keys[name].classList.add("on"); }
    function move(x, y) { pointer.style.left = `calc(${x} * var(--k))`; pointer.style.top = `calc(${y} * var(--k))`; }
    function click() { pointer.classList.remove("click"); void pointer.offsetWidth; pointer.classList.add("click"); }
    function at(ms, fn) { timers.push(setTimeout(fn, reduced ? 0 : ms)); }
    function clear() { timers.forEach(clearTimeout); timers = []; }
    function mark(i) { stepIndex = i; stepBtns.forEach((b) => b.toggleAttribute("aria-current", false)); if (stepBtns[i]) stepBtns[i].setAttribute("aria-current", "step"); }

    // Initial state.
    function reset() {
      clear(); strip.classList.remove("open", "closing"); sel.classList.remove("on"); hud.classList.remove("on"); key(null);
      ins1.textContent = ""; ins2.textContent = ""; front("mail"); move(52, 32); render(base, null);
    }

    // Steps are absolute times in one loop. Each step can also be started on its own.
    const STEPS = [
      function copy() { // 0: copy in Notes
        mark(0); front("notes"); move(20, 23);
        at(600, () => { sel.classList.add("on"); });
        at(1200, () => { key("copy"); hud.classList.add("on"); mbSp.classList.add("pulse"); });
        at(1900, () => { hud.classList.remove("on"); mbSp.classList.remove("pulse"); });
        at(2400, () => { key(null); next(); });
      },
      function open() { // 1: ⇧⌘V, strip rises with the new card at the front
        mark(1); front("mail"); move(60, 36);
        at(500, () => key("open"));
        at(1000, () => { strip.classList.add("open"); render(["addr"].concat(base), "addr"); });
        at(2300, () => { key(null); next(); });
      },
      function ret() { // 2: Return pastes the address into Mail
        mark(2);
        at(300, () => key("return"));
        at(900, () => { strip.classList.add("closing"); strip.classList.remove("open"); });
        at(1200, () => { ins1.textContent = "Rua Garrett 73, 1200-203 Lisboa\n"; });
        at(2200, () => { key(null); strip.classList.remove("closing"); next(); });
      },
      function pick() { // 3: open again, move the selection to an older card
        mark(3); move(60, 36);
        at(300, () => key("open"));
        at(800, () => { strip.classList.add("open"); render(["addr"].concat(base), "addr"); });
        at(1500, () => key("arrows"));
        at(1700, () => render(["addr"].concat(base), "flight"));
        at(2200, () => render(["addr"].concat(base), "cabin"));
        at(2800, () => { key(null); next(); });
      },
      function dbl() { // 4: double-click the link card; it lands in Mail
        mark(4);
        at(200, () => { move(56, 62); });
        at(900, () => { key("dbl"); click(); });
        at(1400, () => { strip.classList.add("closing"); strip.classList.remove("open"); });
        at(1700, () => { ins2.textContent = "Booking: airbnb.com/rooms/48213"; });
        at(3400, () => { key(null); strip.classList.remove("closing"); render(base, null); next(); });
      },
    ];
    function next() { if (!running) return; const i = (stepIndex + 1) % STEPS.length; if (i === 0) { reset(); at(600, () => STEPS[0]()); } else STEPS[i](); }
    function go(i) { clear(); running = true; // rebuild the state the step expects
      strip.classList.remove("open", "closing"); sel.classList.remove("on"); hud.classList.remove("on"); key(null); front("mail");
      ins1.textContent = i >= 3 ? "Rua Garrett 73, 1200-203 Lisboa\n" : ""; ins2.textContent = "";
      render(i >= 1 ? ["addr"].concat(base) : base, null);
      STEPS[i]();
    }
    function start() { if (running) return; running = true; reset(); at(400, () => STEPS[0]()); }
    function stop() { running = false; clear(); }

    stepBtns.forEach((b) => b.addEventListener("click", () => go(+b.dataset.step)));
    $("[data-replay]")?.addEventListener("click", () => go(0));
    reset();
    if (reduced) { // a still: strip open, a card selected, both pastes done
      strip.classList.add("open"); render(["addr"].concat(base), "cabin"); ins1.textContent = "Rua Garrett 73, 1200-203 Lisboa\n"; ins2.textContent = "Booking: airbnb.com/rooms/48213"; mark(4);
      stepBtns.forEach((b) => b.addEventListener("click", () => go(+b.dataset.step)));
    } else {
      whenVisible(root, start, stop);
    }
  })();

  // ---------- Types gallery ----------
  (function types() {
    const el = $("[data-types]");
    if (!el) return;
    const rows = [
      ["flight", "Text", "Plain text keeps its line breaks. The footer counts characters; the preview shows the first 20 000."],
      ["quote", "Rich text", "Fonts, bold, lists and the text's own background colour survive. ⇧↩ pastes it plain."],
      ["cabin", "Link", "The page's title, domain and preview image, fetched the way a browser would. ⌘O opens it."],
      ["photo", "Image", "The image itself, with its pixel size. Previews show it full size; the clipboard gets the original."],
      ["deck", "File", "Files copied in Finder, with their icon, name and path. ⌘O opens; Reveal in Finder from the menu."],
      ["brand", "Colour", "A #RRGGBB value fills the whole card and reads in light or dark text, whichever is legible."],
    ];
    el.innerHTML = rows.map(([id, name, text], i) => `<figure>${card(byId[id], { selected: i === 2 })}<figcaption><b>${name}</b>${text}</figcaption></figure>`).join("");
  })();

  // ---------- Search playground ----------
  (function search() {
    const input = $("[data-search-input]"), box = $("[data-searchbox]"), tokens = $("[data-search-tokens]"), cards = $("[data-search-cards]"), count = $("[data-search-count]");
    if (!input) return;
    const FILTERS = ["app", "type", "title", "date", "device", "pinboard"];
    const TYPE = { text: "text", texts: "text", rich: "text", richtext: "text", html: "text", link: "link", links: "link", url: "link", urls: "link", image: "image", images: "image", picture: "image", pictures: "image", photo: "image", photos: "image", file: "file", files: "file", color: "color", colors: "color", colour: "color", colours: "color" };
    const KIND = { text: "text", rich: "text", link: "link", image: "image", files: "file", color: "color" };
    const DATES = { today: ["today"], yesterday: ["yesterday"], thisweek: ["today", "yesterday", "week"], last7days: ["today", "yesterday", "week"], thismonth: ["today", "yesterday", "week", "month"], last30days: ["today", "yesterday", "week", "month"], thisyear: ["today", "yesterday", "week", "month", "older"] };

    function parse(text) {
      const words = [], re = /"([^"]*)"?|(\S+)/g; let m;
      while ((m = re.exec(text))) words.push({ t: m[1] !== undefined ? m[1] : m[2], q: m[1] !== undefined });
      const comps = [];
      for (const w of words) {
        const c = w.t.indexOf(":");
        if (!w.q && c > 0 && FILTERS.includes(w.t.slice(0, c).toLowerCase())) {
          let v = w.t.slice(c + 1).replace(/^"|"$/g, "");
          if (v) comps.push({ f: w.t.slice(0, c).toLowerCase(), v });
        } else if (w.t) comps.push({ tok: w.t });
      }
      return comps;
    }
    const norm = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
    function textOf(i) { return [i.title, i.text, i.ltitle, i.url, i.name, i.path, i.hex, i.html?.replace(/<[^>]+>/g, " ")].filter(Boolean).join(" "); }
    function matches(i, comps) {
      const groups = {};
      for (const c of comps) {
        if (c.tok) { const words = norm(textOf(i)).split(/[^\p{L}\p{N}#]+/u); if (!words.some((w) => w.startsWith(norm(c.tok)))) return false; continue; }
        (groups[c.f] ||= []).push(c.v);
      }
      for (const [f, vs] of Object.entries(groups)) {
        const ok = vs.some((v) => {
          const n = norm(v);
          if (f === "app") return norm(APPS[i.app].name).startsWith(n);
          if (f === "type") return TYPE[n] === KIND[i.kind];
          if (f === "device") return norm(i.device).startsWith(n);
          if (f === "pinboard") return (i.pins || []).some((p) => norm(PINBOARDS.find((b) => b.id === p).name) === n);
          if (f === "title") return !!i.title && norm(i.title).includes(n);
          if (f === "date") { const k = n.replace(/[\s_-]/g, ""); return (DATES[k] || []).includes(i.date); }
          return false;
        });
        if (!ok) return false;
      }
      return true;
    }
    function run() {
      const comps = parse(input.value);
      box.classList.toggle("has", input.value.length > 0);
      tokens.innerHTML = comps.filter((c) => c.f).map((c) => `<span class="tok" style="--hdr:${c.f === "pinboard" ? PIN_COLORS[(PINBOARDS.find((b) => norm(b.name) === norm(c.v)) || {}).color] || "var(--ink-3)" : "var(--ink-3)"}"><i></i>${esc(c.f)}:${esc(c.v)}</span>`).join("");
      const hits = ITEMS.filter((i) => matches(i, comps));
      cards.innerHTML = hits.length ? hits.map((i) => card(i)).join("") : `<div class="empty" style="width:100%">Nothing found</div>`;
      count.textContent = comps.length ? `${hits.length} of ${ITEMS.length} items match. Nothing you type here is saved.` : `${ITEMS.length} items in this demo history. Nothing you type here is saved.`;
    }
    input.addEventListener("input", run);
    $("[data-search-clear]").addEventListener("click", () => { input.value = ""; run(); input.focus(); });
    $$("[data-search-try] button").forEach((b) => b.addEventListener("click", () => { input.value = b.dataset.q; run(); input.focus(); }));
    input.addEventListener("keydown", (e) => { if (e.key === "Escape") { input.value = ""; run(); } });
    run();
  })();

  // ---------- Pinboards ----------
  (function pinboards() {
    const demo = $("[data-pin-demo]");
    if (!demo) return;
    const tabsEl = $("[data-pin-tabs]", demo), cardsEl = $("[data-pin-cards]", demo), status = $("[data-pin-status]", demo), pop = $("[data-pin-pop]", demo), nameIn = $("[data-pin-name]", demo), colorsEl = $("[data-pin-colors]", demo);
    const boards = PINBOARDS.map((b) => ({ ...b }));
    const extra = { id: "recipes", name: "Recipes", color: "pink", items: ["quote", "reply"] };
    let lists = [{ id: "history", name: "Clipboard" }].concat(boards), cur = 0, created = false;

    function itemsFor(list) {
      if (list.id === "history") return ITEMS.slice(0, 7);
      if (list.id === extra.id) return extra.items.map((id) => byId[id]);
      return ITEMS.filter((i) => (i.pins || []).includes(list.id));
    }
    function draw() {
      tabsEl.innerHTML = lists.map((l, i) => l.id === "history"
        ? `<button class="tab${i === cur ? " on" : ""}" type="button" data-i="${i}"><svg viewBox="0 0 24 24"><path d="M3 12a9 9 0 1 0 3-6.7"/><path d="M3 4v5h5M12 7v5l3 2"/></svg>Clipboard</button>`
        : `<button class="tab${i === cur ? " on" : ""}" type="button" data-i="${i}" style="--c:${PIN_COLORS[l.color]}"><i class="dot"></i>${esc(l.name)}</button>`).join("") + `<button class="tab add" type="button" data-pin-plus aria-label="Create pinboard">+</button>`;
      const list = lists[cur];
      const items = itemsFor(list);
      cardsEl.innerHTML = items.length ? items.map((i) => card(i, { pinboard: list.id === "history" ? null : list.id, extraPinboards: [extra] })).join("") : `<div class="empty" style="width:100%">Pinboard is empty</div>`;
      status.innerHTML = list.id === "history" ? `<b>Clipboard</b> · the history, headers in app colours` : `<b>${esc(list.name)}</b> · ${items.length} pinned · headers take the pinboard colour`;
      $$("[data-i]", tabsEl).forEach((b) => b.addEventListener("click", () => { cur = +b.dataset.i; pop.classList.remove("on"); draw(); }));
      $("[data-pin-plus]", tabsEl).addEventListener("click", add);
    }
    function add() {
      if (!created) { created = true; lists.push({ ...extra }); }
      cur = lists.length - 1; draw(); pop.classList.add("on"); nameIn.value = lists[cur].name; nameIn.focus(); nameIn.select();
      colorsEl.innerHTML = Object.entries(PIN_COLORS).map(([k, v]) => `<button type="button" class="${lists[cur].color === k ? "on" : ""}" style="--c:${v}" data-c="${k}" aria-label="${k}"><i></i></button>`).join("");
      $$("[data-c]", colorsEl).forEach((b) => b.addEventListener("click", () => { lists[cur].color = b.dataset.c; extra.color = b.dataset.c; draw(); pop.classList.add("on"); $$("[data-c]", colorsEl).forEach((x) => x.classList.toggle("on", x === b)); }));
    }
    nameIn.addEventListener("input", () => { if (lists[cur].id === extra.id) { lists[cur].name = nameIn.value || "Pinboard"; extra.name = lists[cur].name; const t = $$("[data-i]", tabsEl)[cur]; if (t) t.lastChild.textContent = lists[cur].name; status.innerHTML = `<b>${esc(lists[cur].name)}</b> · rename it, pick a colour`; } });
    nameIn.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === "Escape") { pop.classList.remove("on"); demo.focus(); } });
    const step = (d) => { cur = (cur + d + lists.length) % lists.length; pop.classList.remove("on"); draw(); };
    $("[data-pin-prev]", demo).addEventListener("click", () => step(-1));
    $("[data-pin-next]", demo).addEventListener("click", () => step(1));
    $("[data-pin-add]", demo).addEventListener("click", add);
    demo.addEventListener("keydown", (e) => {
      if (e.target === nameIn) return;
      if ((e.metaKey || e.ctrlKey) && e.key === "ArrowRight") { e.preventDefault(); step(1); }
      if ((e.metaKey || e.ctrlKey) && e.key === "ArrowLeft") { e.preventDefault(); step(-1); }
    });
    document.addEventListener("click", (e) => { if (!pop.contains(e.target) && !e.target.closest("[data-pin-plus],[data-pin-add]")) pop.classList.remove("on"); });
    draw();
  })();

  // ---------- Paste Stack ----------
  (function stack() {
    const demo = $("[data-stack-demo]");
    if (!demo) return;
    const list = $("[data-stack-list]", demo), empty = $("[data-stack-empty]", demo), fields = $$("[data-field]", demo), status = $("[data-stack-status]", demo), steps = $$("[data-stack-steps] li");
    const ICON = { text: '<svg viewBox="0 0 24 24"><path d="M4 6h16M4 10h16M4 14h12M4 18h8"/></svg>', link: '<svg viewBox="0 0 24 24"><path d="M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1"/><path d="M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1"/></svg>' };
    const ITEMS3 = [{ t: "Priya Natarajan", k: "text" }, { t: "priya@example.com", k: "link" }, { t: "Rua Garrett 73, 1200-203 Lisboa", k: "text" }];
    const STATES = [
      { stack: [], filled: 0, focus: -1, text: "The clipboard works as usual. Press <b>⇧⌘C</b> to start a Paste Stack." },
      { stack: [], filled: 0, focus: -1, text: "<b>Paste Stack</b> panel opened, empty. Everything you copy now lands in it." },
      { stack: [0, 1, 2], filled: 0, focus: -1, text: "Copied the name, the email, the address from the spreadsheet. Three rows, in order." },
      { stack: [1, 2], filled: 1, focus: 0, text: "Clicked into <b>Name</b>, pressed <b>⌘V</b>: the first item is pasted and leaves the stack." },
      { stack: [], filled: 3, focus: 2, text: "<b>⇥ ⌘V</b>, <b>⇥ ⌘V</b>: email, then address. The stack is empty." },
      { stack: null, filled: 3, focus: -1, text: "<b>⇧⌘C</b> closes the panel. ⌘V is a normal paste again." },
    ];
    let i = 0, timer = null;
    function draw() {
      const s = STATES[i];
      demo.querySelector(".stack-panel").style.opacity = s.stack === null || i === 0 ? 0.35 : 1;
      list.innerHTML = (s.stack || []).map((n, idx) => `<li class="${idx === 0 && s.filled > 0 ? "next" : ""}">${ICON[ITEMS3[n].k]}<span>${esc(ITEMS3[n].t)}</span></li>`).join("");
      empty.style.display = s.stack && s.stack.length ? "none" : "";
      fields.forEach((f, n) => { const was = f.textContent; f.textContent = n < s.filled ? ITEMS3[n].t : ""; f.classList.toggle("focus", n === s.focus); f.classList.toggle("filled", n < s.filled && was !== ITEMS3[n].t); });
      status.innerHTML = s.text;
      steps.forEach((li, n) => li.classList.toggle("on", n === i - 1));
    }
    const go = (n) => { i = (n + STATES.length) % STATES.length; draw(); };
    $("[data-stack-next]", demo).addEventListener("click", () => { stopPlay(); go(i + 1); });
    $("[data-stack-prev]", demo).addEventListener("click", () => { stopPlay(); go(i - 1); });
    const playBtn = $("[data-stack-play]", demo);
    function stopPlay() { if (timer) { clearInterval(timer); timer = null; playBtn.textContent = "Play"; } }
    playBtn.addEventListener("click", () => { if (timer) return stopPlay(); go(0); playBtn.textContent = "Stop"; timer = setInterval(() => { if (i === STATES.length - 1) return stopPlay(); go(i + 1); }, 1700); });
    whenVisible(demo, () => {}, stopPlay);
    draw();
  })();

  // ---------- Paste anywhere ----------
  (function paste() {
    const demo = $("[data-paste-demo]");
    if (!demo) return;
    const cards = $("[data-paste-cards]", demo), strip = $("[data-paste-strip]", demo);
    const ids = ["addr", "flight", "cabin", "photo", "brand", "rebase", "deck", "quote", "repo"];
    cards.innerHTML = ids.map((id, n) => card(byId[id], { number: n + 1, plain: true, selected: n === 0 })).join("");
    $$("[data-hold]", demo).forEach((b) => b.addEventListener("click", () => {
      const on = b.getAttribute("aria-pressed") !== "true";
      $$("[data-hold]", demo).forEach((x) => x.setAttribute("aria-pressed", "false"));
      b.setAttribute("aria-pressed", String(on));
      strip.classList.toggle("show-badges", on && b.dataset.hold === "cmd");
      strip.classList.toggle("show-plain", on && b.dataset.hold === "shift");
    }));
    $$("[data-mode]", demo).forEach((b) => b.addEventListener("click", () => {
      $$("[data-mode]", demo).forEach((x) => { x.classList.toggle("on", x === b); x.setAttribute("aria-pressed", String(x === b)); });
    }));
  })();

  // ---------- Hot corner peek ----------
  (function peek() {
    const demo = $("[data-peek-demo]");
    if (!demo) return;
    const strip = $("[data-peek-strip]", demo), corner = $("[data-peek-corner]", demo), pointer = $("[data-peek-pointer]", demo), status = $("[data-peek-status]", demo);
    strip.innerHTML = ["addr", "cabin", "photo"].map((id) => card(byId[id])).join("");
    let timers = [];
    const at = (ms, fn) => timers.push(setTimeout(fn, reduced ? 0 : ms));
    function play() {
      timers.forEach(clearTimeout); timers = [];
      strip.classList.remove("on"); corner.classList.remove("on"); pointer.style.left = "60%"; pointer.style.top = "40%";
      status.textContent = "Move the pointer into the corner…";
      at(600, () => { pointer.style.left = "0.5%"; pointer.style.top = "95%"; });
      at(1600, () => { corner.classList.add("on"); status.textContent = "Resting in the bottom-left corner."; });
      at(1900, () => { strip.classList.add("on"); status.textContent = "The peek slides out: your three latest items, no shortcut."; });
      at(4200, () => { pointer.style.left = "55%"; pointer.style.top = "45%"; });
      at(5300, () => { strip.classList.remove("on"); corner.classList.remove("on"); status.textContent = "Move away and it's gone 0.6 s later. Replay to see it again."; });
    }
    $("[data-peek-replay]", demo).addEventListener("click", play);
    if (reduced) { strip.classList.add("on"); corner.classList.add("on"); pointer.style.left = "0.5%"; pointer.style.top = "95%"; status.textContent = "The pointer rests in the corner and the peek shows."; }
    else whenVisible(demo, play, () => { timers.forEach(clearTimeout); });
  })();

  // ---------- Sync diagram ----------
  whenVisible($("[data-sync]"), () => $("[data-sync]").classList.add("run"), () => $("[data-sync]").classList.remove("run"));
})();
