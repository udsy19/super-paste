/* Super Paste website. The product pictures are drawn from one card component, one strip and one small demo
   history; nothing a visitor does here is stored or sent anywhere. Scrolling is left to the browser: nothing here
   moves the page except anchor links the visitor clicks. */
(() => {
  "use strict";
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));
  const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
  const root = document.documentElement;

  // ---------- Apps, pinboards and the demo history ----------
  const APPS = {
    safari: { name: "Safari", hdr: "#1A8CFF", icon: "ic-safari" },
    notes: { name: "Notes", hdr: "#F2B600", icon: "ic-notes" },
    mail: { name: "Mail", hdr: "#1A7CF2", icon: "ic-mail" },
    photos: { name: "Photos", hdr: "#FF3B30", icon: "ic-photos" },
    finder: { name: "Finder", hdr: "#2F86F6", icon: "ic-finder" },
    terminal: { name: "Terminal", hdr: "#3A3A3C", icon: "ic-terminal" },
    meter: { name: "Digital Color Meter", hdr: "#2D6CF6", icon: "ic-meter" },
    pages: { name: "Pages", hdr: "#FA9214", icon: "ic-pages" },
    xcode: { name: "Xcode", hdr: "#1C7CF4", icon: "ic-xcode" },
    messages: { name: "Messages", hdr: "#30C552", icon: "ic-messages" },
    maps: { name: "Maps", hdr: "#34C759", icon: "ic-maps" },
    passwords: { name: "Passwords", hdr: "#8E8E93", icon: "ic-passwords" },
    design: { name: "Sketchpad", hdr: "#A55EEA", icon: "ic-design" },
    editor: { name: "Code", hdr: "#16213A", icon: "ic-editor" },
    calendar: { name: "Calendar", hdr: "#FF3B30", icon: "ic-calendar" },
    books: { name: "Books", hdr: "#FF8A0A", icon: "ic-books" },
    shortcuts: { name: "Shortcuts", hdr: "#5856D6", icon: "ic-shortcuts" },
  };
  const PINS = {
    travel: { name: "Travel", c: "#FA9214" },
    work: { name: "Work", c: "#B663E0" },
    snippets: { name: "Snippets", c: "#34C759" },
    commands: { name: "Commands", c: "#0A84FF" },
    colours: { name: "Colours", c: "#FF2D55" },
    icons: { name: "Icons", c: "#5856D6" },
    replies: { name: "Replies", c: "#34C759" },
    quotes: { name: "Quotes", c: "#FF9500" },
  };
  const TYPE_TOKENS = { link: { name: "Link", icon: "i-link" } };

  const code = (src) => esc(src)
    .replace(/(&quot;[^&]*?&quot;|'[^']*')/g, '<span class="s">$1</span>')
    .replace(/\b(let|var|func|SELECT|FROM|WHERE|ORDER BY|LIMIT|DESC|true|false)\b/g, '<span class="k">$1</span>')
    .replace(/\b(\d+)\b/g, '<span class="n">$1</span>');

  // kind: text | code | rich | link | image | color | files | secret
  const ITEMS = {
    addr: { kind: "text", app: "notes", when: "2 minutes ago", text: "Hotel\nRua Garrett 73\n1200-203 Lisboa\nPortugal" },
    flight: { kind: "text", app: "mail", when: "25 minutes ago", text: "UA 1931 — SFO → EWR\nSeptember 12, 7:05 AM\nConfirmation: K7Q2LM\n\nUnited Airlines" },
    cabin: { kind: "link", app: "safari", when: "2 hours ago", title: "Cabin near Muir Woods with a view", host: "airbnb.com", art: "dunes", url: "https://www.airbnb.com/rooms/48213" },
    photo: { kind: "image", app: "photos", when: "4 hours ago", art: "bloom", size: "4032 × 3024" },
    brand: { kind: "color", app: "meter", when: "5 hours ago", hex: "#FF6B35" },
    rebase: { kind: "code", app: "terminal", when: "Yesterday", text: "git rebase -i HEAD~3 && git push --force-with-lease origin strip" },
    deck: { kind: "files", app: "finder", when: "Yesterday", icon: "ic-keynote", path: "~/Documents/Offsite/Offsite deck v4.key" },
    repo: { kind: "link", app: "safari", when: "3 days ago", title: "udsy19/super-paste: a clipboard manager for Mac", host: "github.com", art: "repo" },
    quote: { kind: "rich", app: "pages", when: "3 days ago", html: "<b>Offsite agenda</b><br>1. Lisbon <i>logistics</i><br>2. Q4 roadmap<br>3. Hiring plan", chars: 52 },
    reply: { kind: "text", app: "mail", when: "Last week", title: "Invoice reply", text: "Thanks for the invoice. It's been approved and will be paid on the next run, within 14 days." },
    swift: { kind: "code", app: "xcode", when: "Last week", text: "let query = SearchQuery(\n  parsing: \"app:Mail type:link\")\nlet items = store.search(\n  query, limit: 20)" },
    note: { kind: "text", app: "notes", when: "just now", text: "Pick up the film from the lab before 6. Ask about the 120 rolls." },
    maps: { kind: "link", app: "maps", when: "35 minutes ago", title: "Harbour Street Bakery", host: "maps.apple.com", art: "map" },
    launch: { kind: "text", app: "messages", when: "1 hour ago", text: "Launch list:\n• Release notes\n• DMG and its SHA-256\n• Post the changelog" },
    lake: { kind: "link", app: "safari", when: "just now", title: "Emerald Bay loop trail", host: "trailnotes.org", art: "lake" },
    lisbon: { kind: "link", app: "safari", when: "Yesterday", title: "Lisbon rooftops worth the climb", host: "atlas-travel.co", art: "night" },
    tram: { kind: "image", app: "photos", when: "Yesterday", art: "bridge", size: "4032 × 3024" },
    list: { kind: "text", app: "notes", when: "1 hour ago", text: "Packing list:\n• Rain jacket\n• Hiking boots\n• Camera\n• Charger" },
    sign: { kind: "text", app: "mail", when: "2 weeks ago", title: "Signature", text: "Kind regards,\nInes Moreau\nEditor, Field Notes" },
    thanks: { kind: "text", app: "mail", when: "3 weeks ago", title: "Thanks", text: "Thanks for sending this over. I'll read it properly tonight and come back to you tomorrow." },
    follow: { kind: "text", app: "mail", when: "Last month", title: "Follow-up", text: "Just following up on my note from last week. Is the 24th still good for you?" },
    decline: { kind: "text", app: "mail", when: "Last month", title: "Not now", text: "Thank you for thinking of us. We can't take this on right now, but please keep us in mind." },
    meet: { kind: "text", app: "calendar", when: "Last month", title: "Availability", text: "Free Tuesday 10–12 or Thursday after 3. Pick whatever suits you." },
    intro: { kind: "text", app: "mail", when: "2 months ago", title: "Introduction", text: "Hi both, introducing you as promised. Daniel writes about coastlines; Maya draws the maps." },
    sql: { kind: "code", app: "editor", when: "2 days ago", text: "SELECT id, title\nFROM items\nWHERE kind = 'link'\nORDER BY created DESC\nLIMIT 20;" },
    json: { kind: "code", app: "editor", when: "3 days ago", text: "{\n  \"mcpServers\": {\n    \"super-paste\": {\n      \"url\": \"http://127.0.0.1:39725/mcp\"\n    }\n  }\n}" },
    regex: { kind: "code", app: "editor", when: "Last week", text: "^(?<user>[\\w.+-]+)@(?<host>[\\w-]+\\.[\\w.]+)$" },
    curl: { kind: "code", app: "terminal", when: "Last week", text: "curl -fsSL https://udsy19.github.io/super-paste/install.sh | bash" },
    "cmd-build": { kind: "text", app: "terminal", when: "now", text: "swift build -c release" },
    "cmd-test": { kind: "text", app: "terminal", when: "now", text: "swift run SuperPasteSelfTest" },
    "cmd-run": { kind: "text", app: "terminal", when: "now", text: "open \"build/Super Paste.app\"" },
    "cmd-add": { kind: "text", app: "terminal", when: "now", text: "git add -p Sources/StripKit" },
    "cmd-commit": { kind: "text", app: "terminal", when: "now", text: "git commit -m \"Strip: slide up from the screen with the pointer\"" },
    "cmd-push": { kind: "text", app: "terminal", when: "now", text: "git push origin main" },
    "c-orange": { kind: "color", app: "meter", when: "2 days ago", title: "Red Orange", hex: "#FF6B35" },
    "c-butter": { kind: "color", app: "meter", when: "2 days ago", title: "Butter", hex: "#FFD27A", on: "#5A4100" },
    "c-sky": { kind: "color", app: "meter", when: "3 days ago", title: "Sky", hex: "#8EC5FF", on: "#0B3B73" },
    "c-mint": { kind: "color", app: "meter", when: "3 days ago", title: "Mint", hex: "#A8E6CF", on: "#14503A" },
    "c-navy": { kind: "color", app: "meter", when: "Last week", title: "Navy", hex: "#1F3A93" },
    "c-rose": { kind: "color", app: "meter", when: "Last week", title: "Rose", hex: "#F7A1C4", on: "#6B1238" },
    "chart-link": { kind: "link", app: "safari", when: "now", title: "Shipping emissions, 2020–2025", host: "ourdata.studio", art: "chart" },
    "poster-link": { kind: "link", app: "safari", when: "3 minutes ago", title: "Grotesk Display, a type specimen", host: "letterworks.studio", art: "poster" },
    "forest-link": { kind: "link", app: "messages", when: "3 hours ago", title: "Ten quiet walks near the city", host: "outdoors.guide", art: "forest" },
    "ceramic-link": { kind: "link", app: "safari", when: "10 minutes ago", title: "Ceramics for small kitchens", host: "makersmarket.shop", art: "ceramic" },
    "bridge-link": { kind: "link", app: "safari", when: "2 hours ago", title: "Golden hour from the south pier", host: "photoroll.blog", art: "bridge" },
    "dunes-img": { kind: "image", app: "photos", when: "2 weeks ago", art: "dunes", size: "1890 × 1890" },
    "bloom-img": { kind: "image", app: "design", when: "2 weeks ago", art: "bloom", size: "2400 × 2400" },
    "night-img": { kind: "image", app: "photos", when: "3 minutes ago", art: "night", size: "3024 × 4032" },
    define: { kind: "rich", app: "books", when: "6 days ago", html: "<b>serendipity</b> <i>noun</i><br><br>finding something good without looking for it, like the link you copied last spring.", chars: 98 },
    essay: { kind: "text", app: "pages", when: "now", title: "Draft", text: "Why local-first matters\n\nThe best clipboard is the one you never think about. It keeps what you copy on the machine you copied it on, and gets out of the way." },
    "rich-pitch": { kind: "rich", app: "pages", when: "2 hours ago", rbg: "#FFF6D6", html: "<b>Q4 plan</b><br><br>Ship folder sync to everyone, then polish search: filters as tokens, faster results, fewer clicks.", chars: 104 },
    "secret-wifi": { kind: "secret", app: "passwords", label: "Wi-Fi password", text: "•••• •••• ••••" },
    "secret-bank": { kind: "secret", app: "passwords", label: "Bank login", text: "8Fj6Ku1fR3402x~f9=\"23(b7:8`2&A2rY" },
    "secret-zip": { kind: "secret", app: "passwords", label: "API token", text: "sk_live_51H8xK2eZvKYlo2C9QW" },
    "secret-keys": { kind: "secret", app: "passwords", label: "Recovery codes", text: "k7#Pq9!vR2zT&bL4\nG#4t9Vm^s1yT6!rL\nZp8$kQ3&fV0m4^Wx" },
  };

  const KIND = { text: "Text", code: "Text", rich: "Text", link: "Link", image: "Image", color: "Color", files: "File", secret: "Password" };

  function card(id, o = {}) {
    const it = ITEMS[id];
    if (!it) return "";
    const app = APPS[it.app];
    const pin = o.pin && PINS[o.pin];
    const hdr = pin ? pin.c : app.hdr;
    const title = (pin || o.titles) && it.title ? it.title : KIND[it.kind];
    if (it.kind === "secret") {
      return `<div class="card secret-card"><div class="card-in"><div class="card-hd" style="--hdr:${app.hdr}"><div class="lab"><b>${esc(it.label)}</b><span>Not saved</span></div><svg class="app"><use href="#${app.icon}"/></svg></div>` +
        `<div class="card-bd secret"><b>${esc(app.name)}</b><em>${esc(it.text)}</em></div><div class="card-ft">Never saved</div><span class="lock"><svg><use href="#i-lock"/></svg></span></div></div>`;
    }
    const head = `<div class="card-hd" style="--hdr:${hdr}"><div class="lab"><b>${esc(title)}</b><span>${esc(it.when)}</span></div>${pin ? '<i class="pin"></i>' : `<svg class="app"><use href="#${app.icon}"/></svg>`}</div>`;
    let body = "";
    let foot = "";
    switch (it.kind) {
      case "text":
        body = `<div class="card-bd text">${esc(it.text)}</div>`;
        foot = `<div class="card-ft">${it.text.length} characters</div>`;
        break;
      case "code":
        body = `<div class="card-bd text mono">${code(it.text)}</div>`;
        foot = `<div class="card-ft">${it.text.length} characters</div>`;
        break;
      case "rich":
        body = `<div class="card-bd text rich" style="--rbg:${it.rbg || "#fff"}">${it.html}</div>`;
        foot = `<div class="card-ft" style="--ftbg:${it.rbg || "#fff"}">${it.chars} characters</div>`;
        break;
      case "link":
        body = `<div class="card-bd link"><div class="pv"><svg class="art"><use href="#art-${it.art}"/></svg></div><div class="meta"><b>${esc(it.title)}</b><span>${esc(it.host)}</span></div></div>`;
        break;
      case "image":
        body = `<div class="card-bd image"><svg class="art"><use href="#art-${it.art}"/></svg><span class="pill">${it.size}</span></div>`;
        break;
      case "color":
        body = `<div class="card-bd color" style="--c:${it.hex};--on:${it.on || "#fff"}">${it.hex}</div>`;
        break;
      case "files":
        body = `<div class="card-bd files"><svg><use href="#${it.icon}"/></svg><span>${esc(it.path)}</span></div>`;
        break;
    }
    return `<div class="card${o.sel ? " sel" : ""}" data-id="${id}"><div class="card-in">${head}${body}${foot}</div></div>`;
  }

  // ---------- Strip: toolbar and cards ----------
  // One toolbar for both modes: the magnifier grows into the search field and the tabs fold into dots.
  const TOKEN = (t) => {
    if (PINS[t]) return `<span class="tok"><i style="--c:${PINS[t].c}"></i>${PINS[t].name}</span>`;
    if (TYPE_TOKENS[t]) return `<span class="tok"><svg><use href="#${TYPE_TOKENS[t].icon}"/></svg>${TYPE_TOKENS[t].name}</span>`;
    if (APPS[t]) return `<span class="tok"><svg><use href="#${APPS[t].icon}"/></svg>${APPS[t].name}</span>`;
    return "";
  };
  function tabsHTML(list) {
    const tabs = list.split(",");
    const anyOn = tabs.some((t) => t.endsWith("*"));
    return tabs.map((t) => {
      const on = t.endsWith("*");
      const key = t.replace("*", "");
      if (key === "clip") return `<span class="tab${on || !anyOn ? " on" : ""}" data-tab="clip"><svg><use href="#i-history"/></svg>Clipboard</span>`;
      if (key === "plus") return `<span class="tb-i"><svg><use href="#i-plus"/></svg></span>`;
      return `<span class="tab${on ? " on" : ""}" data-tab="${key}"><i style="--c:${PINS[key].c}"></i>${PINS[key].name}</span>`;
    }).join("");
  }
  function toolbar(el) {
    const search = el.dataset.search !== undefined;
    const [tokens, query] = search ? el.dataset.search.split("|") : ["", ""];
    const toks = tokens.split(",").filter(Boolean).map(TOKEN).join("");
    const dots = ["travel", "work", "snippets", "commands"].map((p) => `<i class="tb-dot" style="--c:${PINS[p].c}"></i>`).join("");
    return `<div class="tb${search ? " is-search" : ""}"><span class="sfield${search ? " focus" : ""}"><svg><use href="#i-search"/></svg><span class="sf-in">${toks}<span class="q">${esc(query || "")}</span></span><span class="tail"><svg><use href="#i-clear"/></svg><svg><use href="#i-filter"/></svg></span></span>` +
      `<span class="tb-tabs">${tabsHTML(el.dataset.tabs || "clip,travel,work,snippets,plus")}</span><span class="tb-dots"><span class="tb-i on"><svg><use href="#i-history"/></svg></span>${dots}</span><svg class="tb-more"><use href="#i-more"/></svg><div class="sugg"></div></div>`;
  }
  const cardsHTML = (ids, o = {}) => ids.split(",").filter(Boolean).map((id) => (id === "_" ? '<span class="slot"></span>' : card(id, { sel: id === o.sel, pin: o.pin }))).join("");
  function renderStrip(el) {
    el.innerHTML = `${toolbar(el)}<div class="cards">${cardsHTML(el.dataset.cards || "", { sel: el.dataset.sel, pin: el.dataset.pin })}</div>`;
  }

  function renderStack(el) {
    const rows = el.dataset.stack.split(",").map((id, i) => {
      const it = ITEMS[id];
      let icon = "i-lines";
      let text = it.text || "";
      if (it.kind === "link") { icon = "i-link"; text = it.url || `https://${it.host}`; }
      if (it.kind === "image") { icon = "i-doc"; text = `Image ${it.size}`; }
      if (it.kind === "color") { text = it.hex; }
      const glyph = it.kind === "color" ? `<svg style="color:${it.hex}"><use href="#i-swatch"/></svg>` : `<svg><use href="#${icon}"/></svg>`;
      return `<div class="sp-row${i === 0 ? " next" : ""}">${glyph}<span>${esc(text.replace(/\n+/g, " "))}</span></div>`;
    }).join("");
    el.innerHTML = `<div class="sp-in"><div class="sp-hd"><svg class="x"><use href="#i-close"/></svg>Paste Stack<svg class="so"><use href="#i-sort"/></svg></div>${rows}</div>`;
  }

  $$("[data-strip]").forEach(renderStrip);
  $$("[data-stack]").forEach(renderStack);
  $$("[data-card]").forEach((el) => { el.insertAdjacentHTML("afterbegin", card(el.dataset.card, { sel: el.dataset.sel === "1" })); });
  $$("[data-row]").forEach((el) => { el.innerHTML = el.dataset.row.split(",").map((id) => card(id)).join(""); });

  // ---------- Header: frost on scroll, inverted over dark sections, drop-down, menu ----------
  const frost = $(".frost");
  if (frost && !(window.CSS && CSS.supports("animation-timeline: scroll()"))) {
    let ticking = false;
    const paint = () => { ticking = false; frost.style.opacity = String(Math.min(1, window.scrollY / 69)); };
    addEventListener("scroll", () => { if (!ticking) { ticking = true; requestAnimationFrame(paint); } }, { passive: true });
    paint();
  }

  const darkSections = $$("[data-invert-header]");
  let invertIO = null;
  const watchInvert = () => {
    if (invertIO) invertIO.disconnect();
    const under = new Set();
    invertIO = new IntersectionObserver((entries) => {
      entries.forEach((e) => (e.isIntersecting ? under.add(e.target) : under.delete(e.target)));
      root.toggleAttribute("data-header-invert", under.size > 0);
    }, { rootMargin: `0px 0px ${-(innerHeight - 72)}px 0px` });
    darkSections.forEach((s) => invertIO.observe(s));
  };
  if (darkSections.length) { watchInvert(); addEventListener("resize", watchInvert); }

  // A click on a drop-down link closes the panel until the pointer leaves.
  $$(".dd-panel a").forEach((a) => a.addEventListener("click", () => {
    const dd = a.closest(".dd");
    dd.classList.add("collapsed");
    a.blur();
    dd.addEventListener("mouseleave", () => dd.classList.remove("collapsed"), { once: true });
  }));

  const burger = $("[data-burger]");
  const menu = $("[data-menu]");
  const outside = [$("main"), $("footer")];
  function setMenu(open) {
    root.classList.toggle("menu-open", open);
    burger.setAttribute("aria-expanded", String(open));
    burger.setAttribute("aria-label", open ? "Close menu" : "Open menu");
    outside.forEach((el) => el && (el.inert = open));
  }
  if (burger && menu) {
    burger.addEventListener("click", () => setMenu(!root.classList.contains("menu-open")));
    $$("a", menu).forEach((a) => a.addEventListener("click", () => setMenu(false)));
    addEventListener("keydown", (e) => { if (e.key === "Escape" && root.classList.contains("menu-open")) { setMenu(false); burger.focus({ preventScroll: true }); } });
    matchMedia("(min-width: 62.5rem)").addEventListener("change", (m) => { if (m.matches) setMenu(false); });
  }

  // ---------- Reveal on scroll ----------
  const rise = $$(".rise-in");
  if ("IntersectionObserver" in window) {
    const io = new IntersectionObserver((entries) => entries.forEach((e) => {
      if (e.isIntersecting) { e.target.dataset.revealed = ""; io.unobserve(e.target); }
    }), { rootMargin: "0px 0px -15% 0px" });
    rise.forEach((el) => io.observe(el));
  } else {
    rise.forEach((el) => { el.dataset.revealed = ""; });
  }

  // ---------- Carousel: moves its own track sideways, never the page ----------
  (function carousel() {
    const box = $("[data-carousel]");
    if (!box) return;
    const track = $("[data-track]", box);
    const items = Array.from(track.children);
    const dots = $$("[data-dots] button", box);
    const prev = $("[data-prev]", box);
    const next = $("[data-next]", box);
    let current = 0;
    let frame = null;

    const ease = (t) => {
      // cubic-bezier(.4, 0, .2, 1) solved for x by bisection.
      const b = (u, p1, p2) => 3 * (1 - u) ** 2 * u * p1 + 3 * (1 - u) * u ** 2 * p2 + u ** 3;
      let lo = 0, hi = 1, u = .5;
      for (let i = 0; i < 20; i++) { u = (lo + hi) / 2; if (b(u, .4, .2) < t) lo = u; else hi = u; }
      return b(u, 0, 1);
    };
    function glide(i) {
      const target = items[i];
      if (!target) return;
      const pad = parseFloat(getComputedStyle(track).paddingLeft) || 0;
      const to = target.offsetLeft - pad;
      const from = track.scrollLeft;
      if (frame) cancelAnimationFrame(frame);
      if (from === to || reduced) { delete track.dataset.gliding; track.scrollLeft = to; return; }
      const start = performance.now();
      track.dataset.gliding = "";
      const step = (now) => {
        const t = Math.min(1, (now - start) / 700);
        track.scrollLeft = from + (to - from) * ease(t);
        if (t < 1) { frame = requestAnimationFrame(step); return; }
        frame = null;
        delete track.dataset.gliding;
      };
      frame = requestAnimationFrame(step);
    }
    function show(i) {
      current = i;
      dots.forEach((d, k) => (k === i ? d.setAttribute("aria-current", "true") : d.removeAttribute("aria-current")));
      prev.disabled = i === 0;
      next.disabled = i === items.length - 1;
      items.forEach((li, k) => {
        let jump = $(".car-jump", li);
        if (k === i) { if (jump) jump.remove(); return; }
        if (!jump) {
          jump = document.createElement("button");
          jump.type = "button";
          jump.className = "car-jump";
          jump.tabIndex = -1;
          jump.setAttribute("aria-hidden", "true");
          jump.addEventListener("click", () => glide(k));
          li.appendChild(jump);
        }
      });
    }
    const io = new IntersectionObserver((entries) => entries.forEach((e) => {
      if (e.isIntersecting) { const k = items.indexOf(e.target); if (k !== -1 && k !== current) show(k); }
    }), { root: track, threshold: .6 });
    items.forEach((li) => io.observe(li));
    dots.forEach((d, k) => d.addEventListener("click", () => glide(k)));
    prev.addEventListener("click", () => glide(Math.max(0, current - 1)));
    next.addEventListener("click", () => glide(Math.min(items.length - 1, current + 1)));
    show(0);
  })();

  // ---------- Use-case tabs ----------
  (function tabs() {
    const box = $("[data-usecases]");
    if (!box) return;
    const seg = $(".seg", box);
    const btns = $$("[role=tab]", seg);
    const panel = $("[role=tabpanel]", box);
    const caps = $$(".uc-cap", box);
    const shots = $$(".uc-shot", box);
    let index = 0;
    const place = () => {
      const b = btns[index];
      seg.style.setProperty("--seg-x", `${b.offsetLeft}px`);
      seg.style.setProperty("--seg-w", `${b.offsetWidth}px`);
    };
    function select(i, focus) {
      index = (i + btns.length) % btns.length;
      btns.forEach((b, k) => { b.setAttribute("aria-selected", String(k === index)); b.tabIndex = k === index ? 0 : -1; });
      panel.setAttribute("aria-labelledby", btns[index].id);
      caps.forEach((c, k) => { const on = k === index; c.classList.toggle("on", on); c.inert = !on; c.toggleAttribute("aria-hidden", !on); });
      shots.forEach((s, k) => { const on = k === index; s.classList.toggle("on", on); s.toggleAttribute("aria-hidden", !on); });
      place();
      if (focus) {
        const b = btns[index];
        b.focus({ preventScroll: true });
        // Keep the chosen tab inside the pill bar when it scrolls sideways on a phone.
        if (b.offsetLeft < seg.scrollLeft) seg.scrollLeft = b.offsetLeft - 4;
        else if (b.offsetLeft + b.offsetWidth > seg.scrollLeft + seg.clientWidth) seg.scrollLeft = b.offsetLeft + b.offsetWidth - seg.clientWidth + 4;
      }
    }
    btns.forEach((b, k) => {
      b.addEventListener("click", () => select(k, false));
      b.addEventListener("keydown", (e) => {
        const d = e.key === "ArrowRight" || e.key === "ArrowDown" ? 1 : e.key === "ArrowLeft" || e.key === "ArrowUp" ? -1 : 0;
        if (d) { e.preventDefault(); select(index + d, true); }
        else if (e.key === "Home") { e.preventDefault(); select(0, true); }
        else if (e.key === "End") { e.preventDefault(); select(btns.length - 1, true); }
      });
    });
    select(0, false);
    new ResizeObserver(place).observe(seg);
    requestAnimationFrame(() => seg.setAttribute("data-ready", ""));
  })();

  // ---------- Product demos ----------
  // Each demo is a timeline that plays while at least half of it is on screen, the way the reference's videos do:
  // one-shot demos rewind when they leave, the looping one pauses and carries on. Phones and Reduce Motion get the
  // still picture (the reference shows a still image there too).
  const wide = matchMedia("(min-width: 40rem)");
  function timeline(el, { length, steps, reset, loop = false }) {
    let timers = [];
    let pos = 0;
    let startedAt = 0;
    let playing = false;
    let ended = false;
    let touched = false;
    const clear = () => { timers.forEach(clearTimeout); timers = []; };
    function play() {
      if (playing || ended) return;
      if (pos === 0) reset();
      touched = true;
      playing = true;
      startedAt = performance.now() - pos;
      steps.forEach(([at, fn]) => { if (pos === 0 ? at >= 0 : at > pos) timers.push(setTimeout(fn, at - pos)); });
      timers.push(setTimeout(() => {
        clear();
        playing = false;
        pos = 0;
        if (loop) play(); else ended = true;
      }, length - pos));
    }
    function pause() {
      clear();
      if (loop) { if (playing) pos = performance.now() - startedAt; }
      else { pos = 0; ended = false; if (touched) reset(); }
      playing = false;
    }
    new IntersectionObserver(([e]) => {
      if (e.intersectionRatio >= .499 && wide.matches) play(); else pause();
    }, { threshold: [0, .5] }).observe(el);
  }
  const later = (fn) => requestAnimationFrame(() => requestAnimationFrame(fn));
  // Puts a demo pointer over the middle of an element (positions are relative to the pointer's screen).
  function point(cursor, target, dx = 0, dy = 0) {
    const box = cursor.parentElement.getBoundingClientRect();
    const r = target.getBoundingClientRect();
    cursor.style.left = `${r.left - box.left + r.width / 2 + dx}px`;
    cursor.style.top = `${r.top - box.top + r.height / 2 + dy}px`;
  }
  const press = (el) => { el.classList.add("press"); setTimeout(() => el.classList.remove("press"), 140); };
  function setSearch(strip, { tokens = [], q = "" }) {
    $(".tb", strip).classList.add("is-search");
    $(".sfield", strip).classList.add("focus");
    $(".sf-in", strip).innerHTML = tokens.map(TOKEN).join("") + `<span class="q">${esc(q)}</span>`;
  }
  function suggest(strip, rows) {
    const box = $(".sugg", strip);
    if (!rows) { box.classList.remove("on"); return; }
    const icon = (k) => (PINS[k] ? `<i style="--c:${PINS[k].c}"></i>` : k === "link" ? '<svg><use href="#i-link"/></svg>' : k === "date" ? '<svg><use href="#ic-calendar"/></svg>' : `<svg><use href="#${APPS[k].icon}"/></svg>`);
    box.innerHTML = rows.map(([k, label], i) => `<span class="${i === 0 ? "hi" : ""}">${icon(k)}${label}</span>`).join("");
    box.style.left = `${$(".sfield", strip).offsetLeft}px`;
    box.classList.add("on");
  }
  function swap(strip, ids, o = {}) {
    const row = $(".cards", strip);
    row.classList.add("fade");
    setTimeout(() => {
      row.innerHTML = cardsHTML(ids, o);
      row.classList.toggle("slide-in", !!o.slide);
      $$(".card", row).forEach((c, i) => { c.style.animationDelay = `${i * 60}ms`; });
      row.classList.remove("fade");
    }, 250);
  }

  // Direct paste: 8.3 s loop.
  (function film() {
    const el = $("[data-film]");
    if (!el) return;
    const strip = $(".film-strip", el);
    const select = (id) => $$(".card", strip).forEach((c) => c.classList.toggle("sel", c.dataset.id === id));
    const still = () => { el.classList.add("up"); select("cabin"); };
    if (reduced) { still(); return; }
    wide.addEventListener("change", (m) => { if (!m.matches) still(); });
    if (!wide.matches) still();
    const on = (...c) => () => el.classList.add(...c);
    const off = (...c) => () => el.classList.remove(...c);
    timeline(el, {
      length: 8300,
      loop: true,
      reset() {
        el.classList.add("snap");
        el.classList.remove("key", "up", "zoom", "mail", "link", "cur", "press");
        select("list");
        void el.offsetWidth;
        el.classList.remove("snap");
      },
      steps: [
        [0, off("fade")],
        [500, on("key")], [800, on("up")], [1700, off("key")],
        [2900, on("zoom")], [3700, on("cur")],
        [4900, () => { el.classList.add("press"); select("cabin"); }], [5040, off("press")], [5200, on("press")], [5340, off("press")],
        [5600, () => { el.classList.remove("up", "zoom", "cur"); el.classList.add("mail"); }],
        [6000, on("link")],
        [7800, on("fade")],
      ],
    });
  })();

  if (!reduced) {
    // Slide 1: five new copies land at the front of the strip, then it rewinds.
    (function slide1() {
      const stage = $(".s1-stage");
      if (!stage) return;
      const strip = $(".strip", stage);
      const add = (id) => () => {
        const w = document.createElement("span");
        w.className = "ins";
        w.innerHTML = card(id);
        $(".cards", strip).prepend(w);
        later(() => w.classList.add("in"));
      };
      const rewind = () => $$(".ins", strip).forEach((w) => { w.classList.add("out"); w.classList.remove("in"); });
      timeline(stage, {
        length: 7000,
        reset: () => $$(".ins", strip).forEach((w) => w.remove()),
        steps: [[600, add("quote")], [1500, add("tram")], [2500, add("flight")], [3500, add("repo")], [4400, add("addr")], [5300, rewind], [6200, () => $$(".ins", strip).forEach((w) => w.remove())]],
      });
    })();

    // Slide 2: click the magnifier, type, pick a filter token twice; the results change each time.
    (function slide2() {
      const stage = $(".s2-stage");
      if (!stage) return;
      const strip = $(".strip", stage);
      const cur = $(".demo-cursor", stage);
      timeline(stage, {
        length: 7000,
        reset() {
          delete strip.dataset.search;
          strip.dataset.tabs = "clip,travel,work,snippets,plus";
          strip.dataset.cards = "cabin,photo,deck";
          renderStrip(strip);
          cur.classList.remove("on", "press");
          cur.style.left = ""; cur.style.top = "";
        },
        steps: [
          [200, () => cur.classList.add("on")],
          [300, () => point(cur, $(".sfield svg", strip), 4, 6)],
          [1000, () => press(cur)],
          [1100, () => setSearch(strip, {})],
          [1500, () => cur.classList.remove("on")],
          [2100, () => { setSearch(strip, { q: "L" }); suggest(strip, [["link", "Link"], ["date", "Last 7 days"]]); }],
          [3400, () => { suggest(strip, null); setSearch(strip, { tokens: ["link"] }); swap(strip, "cabin,lisbon,repo"); }],
          [4600, () => { setSearch(strip, { tokens: ["link"], q: "S" }); suggest(strip, [["safari", "Safari"], ["snippets", "Snippets"], ["shortcuts", "Shortcuts"]]); }],
          [5300, () => { suggest(strip, null); setSearch(strip, { tokens: ["link", "safari"] }); swap(strip, ""); }],
          [5800, () => swap(strip, "lake,chart-link,ceramic-link")],
        ],
      });
    })();

    // Slide 3: drag a card onto the Snippets tab, then open the pinboard.
    (function slide3() {
      const stage = $(".s3-stage");
      if (!stage) return;
      const scr = $(".scr", stage);
      const strip = $(".strip", stage);
      const cur = $(".demo-cursor", stage);
      let ghost = null;
      const tab = () => $('.tab[data-tab="snippets"]', strip);
      const picked = () => $('.card[data-id="reply"]', strip);
      timeline(stage, {
        length: 7000,
        reset() {
          strip.dataset.tabs = "clip,travel,work,snippets,plus";
          delete strip.dataset.pin;
          strip.dataset.cards = "note,reply,cabin,swift,photo,brand";
          strip.dataset.sel = "";
          renderStrip(strip);
          if (ghost) { ghost.remove(); ghost = null; }
          cur.classList.remove("on", "press");
          cur.style.left = ""; cur.style.top = "";
        },
        steps: [
          [300, () => { cur.classList.add("on"); point(cur, picked(), 10, 10); }],
          [1200, () => { press(cur); picked().classList.add("lift"); }],
          [1450, () => {
            const c = picked();
            const box = scr.getBoundingClientRect();
            const r = c.getBoundingClientRect();
            const t = tab().getBoundingClientRect();
            ghost = document.createElement("div");
            ghost.className = "ghost";
            ghost.style.cssText = `left:${r.left - box.left}px;top:${r.top - box.top}px;--side:${r.width}px`;
            ghost.innerHTML = card("reply");
            scr.appendChild(ghost);
            c.classList.remove("lift");
            c.classList.add("dim");
            later(() => { ghost.style.transform = `translate(${t.left - r.left + t.width / 2 - r.width * .2}px, ${t.top - r.top}px) scale(.4)`; });
            point(cur, tab(), 6, 6);
          }],
          [2250, () => tab().classList.add("drop")],
          [2450, () => {
            ghost.style.opacity = "0";
            const t = tab();
            t.classList.remove("drop");
            t.classList.add("pulse");
            picked().classList.remove("dim");
          }],
          [3600, () => press(cur)],
          [3700, () => {
            $$(".tab", strip).forEach((x) => x.classList.toggle("on", x.dataset.tab === "snippets"));
            swap(strip, "reply,rebase,swift,repo,sign,brand", { pin: "snippets", sel: "reply", slide: true });
          }],
          [4400, () => cur.classList.remove("on")],
        ],
      });
    })();

    // Slide 4: the copied link rises and the three Macs it syncs to appear.
    (function slide4() {
      const stage = $(".s4-stage");
      if (!stage) return;
      timeline(stage, { length: 5000, reset: () => stage.classList.remove("go"), steps: [[700, () => stage.classList.add("go")]] });
    })();

    // The orb at the centre of the MCP plate: drifts on its own, livens up and leans towards a nearby pointer.
    (function orb() {
      const el = $(".orb");
      if (!el) return;
      const a = $(".orb-a", el);
      const b = $(".orb-b", el);
      const lerp = (x, y, t) => x + (y - x) * t;
      let raf = 0;
      let last = 0;
      let phase = 0;
      let ex = 0;
      let sc = 1;
      let ptr = null;
      const pos = [0, 0];
      const vel = [0, 0];
      addEventListener("pointermove", (e) => { ptr = [e.clientX, e.clientY]; }, { passive: true });
      document.documentElement.addEventListener("pointerleave", () => { ptr = null; });
      const shape = (p, k) => {
        const r = (i) => 50 + 7 * k * Math.sin(2 * Math.PI * (p * (1 + i * .13) + i * .37));
        return `${r(0)}% ${100 - r(0)}% ${r(1)}% ${100 - r(1)}% / ${r(2)}% ${r(3)}% ${100 - r(3)}% ${100 - r(2)}%`;
      };
      function frame(now) {
        const dt = Math.min(.05, (now - (last || now)) / 1000);
        last = now;
        const r = el.getBoundingClientRect();
        const cx = r.left + r.width / 2 - pos[0];
        const cy = r.top + r.height / 2 - pos[1];
        const radius = r.width / 2 / sc;
        let inside = false;
        const target = [0, 0];
        if (ptr) {
          const dx = ptr[0] - cx;
          const dy = ptr[1] - cy;
          inside = Math.hypot(dx, dy) < 1.9 * radius;
          if (inside) { target[0] = dx * .205; target[1] = dy * .205; }
        }
        ex += ((inside ? 1 : 0) - ex) * (1 - Math.exp(-dt / .3));
        const live = lerp(.6, 1, ex);
        sc = lerp(1, 1.2, ex);
        phase += dt / lerp(2.5, 1.8, ex);
        const w = 2 * Math.PI * 2.5;
        for (const k of [0, 1]) { vel[k] += (w * w * (target[k] - pos[k]) - 2 * .6 * w * vel[k]) * dt; pos[k] += vel[k] * dt; }
        a.style.borderRadius = shape(phase, live);
        a.style.rotate = `${Math.sin(2 * Math.PI * phase * .5) * 8 * live}deg`;
        b.style.borderRadius = shape(phase + .5, live);
        el.style.transform = `translate(${pos[0].toFixed(2)}px, ${pos[1].toFixed(2)}px) scale(${sc.toFixed(3)})`;
        raf = requestAnimationFrame(frame);
      }
      new IntersectionObserver(([e]) => {
        if (e.isIntersecting && !raf) { last = 0; raf = requestAnimationFrame(frame); }
        else if (!e.isIntersecting && raf) { cancelAnimationFrame(raf); raf = 0; }
      }, { rootMargin: "200px" }).observe(el);
    })();
  }

  // ---------- Copy the install command ----------
  $$("[data-copy]").forEach((b) => b.addEventListener("click", async () => {
    const status = $("[data-copy-status]");
    const text = b.dataset.copy;
    try {
      await navigator.clipboard.writeText(text);
      b.textContent = "Copied";
      if (status) status.textContent = "Copied to the clipboard.";
    } catch (e) {
      const codeEl = b.parentElement.querySelector("code");
      if (codeEl) { const r = document.createRange(); r.selectNodeContents(codeEl); const s = getSelection(); s.removeAllRanges(); s.addRange(r); }
      if (status) status.textContent = "Press ⌘C to copy.";
    }
    setTimeout(() => { b.textContent = "Copy"; if (status) status.textContent = ""; }, 2000);
  }));
})();
