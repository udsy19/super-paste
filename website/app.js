// The strip along the bottom of the page behaves like Super Paste's: what you copy here lands in it, pinboard tabs
// and the search field filter it, and a card copies itself when clicked. Everything lives in memory: nothing is
// stored, nothing is sent, and the clipboard is only ever written to (on a click), never read.
(() => {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  const MIN = 60e3, HOUR = 60 * MIN;

  // Card header colours, one per source app, as the app tints each card with its app's colour.
  const APP_COLOURS = {
    "This page": "#1D3C8F",
    Mail: "#1F6FD1",
    Notes: "#F5C518",
    Figma: "#8B46D9",
    Terminal: "#3A3F45",
    Photos: "#C93A31",
  };
  const BOARDS = {
    clipboard: { name: "Clipboard" },
    travel: { name: "Travel", colour: "#FA9214" },
    work: { name: "Work", colour: "#62A9F5" },
    snippets: { name: "Snippets", colour: "#B663E0" },
  };
  const TYPE_LABELS = { text: "Text", link: "Link", color: "Colour", image: "Image" };
  const TYPE_NAMES = { text: ["text"], link: ["link", "url"], color: ["color", "colour"], image: ["image", "picture"] };
  const CLOCK = '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.25"/><path d="M8 4.6V8l2.4 1.5"/></svg>';
  const MAX_ITEMS = 40;

  let uid = 0;
  const started = Date.now();
  const items = [
    { app: "Mail", type: "link", title: "Casa do Rio, Lisboa: your booking for 14–18 May", content: "https://casadorio.pt/booking/R4417", age: 2 * MIN, boards: ["travel"] },
    { app: "Figma", type: "color", content: "#F2643A", age: 7 * MIN, boards: ["work"] },
    { app: "Terminal", type: "text", code: true, content: "git commit --amend --no-edit", age: 18 * MIN, boards: ["snippets"] },
    { app: "Notes", type: "text", content: "Rua das Flores 28, 2º esq.\n1200-195 Lisboa\nBuzzer says Ferreira", age: 52 * MIN, boards: ["travel", "snippets"] },
    { app: "Photos", type: "image", content: "Rooftops at dusk", size: "1600 × 1200", age: 3 * HOUR, boards: ["travel"] },
    { app: "Mail", type: "text", content: "Thanks, that works. I’ll send the deck by Thursday and we can go through it on Friday.", age: 26 * HOUR, boards: ["work"] },
  ].map((item) => ({ ...item, id: "clip-" + ++uid, t: started - item.age }));

  const strip = $("#strip-panel");
  const list = $("#strip");
  const scroller = $("[data-strip-scroll]");
  const empty = $("[data-strip-empty]");
  const toastEl = $("[data-toast]");
  const live = $("[data-live]");
  const search = $("#search");
  const tabs = $$("[data-board]");
  const tokens = $$("[data-token]");
  const nodes = new Map();

  let board = "clipboard";
  let query = "";
  let selected = null;
  let renderGeneration = 0;
  let shownIds = "";

  // ---------- Helpers ----------

  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const fold = (s) => String(s).normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  const words = (s) => fold(s).split(/[^a-z0-9#]+/).filter(Boolean);
  const plural = (n, one, many) => n + " " + (n === 1 ? one : many);
  const motion = () => !reducedMotion.matches;

  function relativeTime(t) {
    const seconds = (Date.now() - t) / 1000;
    if (seconds < 45) return "now";
    const minutes = Math.max(1, Math.round(seconds / 60));
    if (minutes < 60) return minutes + " min ago";
    const hours = Math.round(minutes / 60);
    if (hours < 24) return hours + " hr ago";
    const days = Math.round(hours / 24);
    return days === 1 ? "Yesterday" : days + " days ago";
  }

  // Ink or white text, whichever contrasts more with the colour.
  function textOn(hex) {
    const v = parseInt(hex.slice(1), 16);
    const lin = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; };
    const lum = 0.2126 * lin(v >> 16) + 0.7152 * lin((v >> 8) & 255) + 0.0722 * lin(v & 255);
    const onWhite = 1.05 / (lum + 0.05), onInk = (lum + 0.05) / 0.056;
    return onInk > onWhite ? "#111215" : "#FFFFFF";
  }

  function host(url) {
    try { return new URL(url).hostname.replace(/^www\./, ""); } catch { return url; }
  }

  function preview(item) {
    const text = item.title || item.content;
    return text.length > 90 ? text.slice(0, 88) + "…" : text;
  }

  function sameDay(a, b) {
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  }

  function dateNames(item) {
    const day = new Date(item.t), today = new Date();
    const yesterday = new Date(today); yesterday.setDate(today.getDate() - 1);
    const names = [];
    if (sameDay(day, today)) names.push("today");
    if (sameDay(day, yesterday)) names.push("yesterday");
    if (Date.now() - item.t < 7 * 24 * HOUR) names.push("week");
    return names;
  }

  // ---------- Search: words match by prefix, filters narrow by app, type, date, device, pinboard or title ----------

  function matches(item, q) {
    const haystack = [item.title || "", item.content, item.app].join(" ");
    for (const raw of q.trim().split(/\s+/).filter(Boolean)) {
      const filter = /^(app|type|date|pinboard|title|device):(.*)$/i.exec(raw);
      if (filter) {
        const key = filter[1].toLowerCase(), value = fold(filter[2]);
        if (!value) continue;
        const ok = {
          app: () => fold(item.app).startsWith(value),
          type: () => TYPE_NAMES[item.type].some((n) => n.startsWith(value)),
          date: () => dateNames(item).some((n) => n.startsWith(value)),
          pinboard: () => item.boards.some((b) => fold(BOARDS[b].name).startsWith(value)),
          title: () => words(item.title || "").some((w) => w.startsWith(value)),
          device: () => "this mac".startsWith(value) || "mac".startsWith(value),
        }[key]();
        if (!ok) return false;
      } else {
        const token = fold(raw);
        const hit = words(haystack).some((w) => w.startsWith(token)) || (/[^a-z0-9]/.test(token) && fold(haystack).includes(token));
        if (!hit) return false;
      }
    }
    return true;
  }

  const inScope = (item) => (board === "clipboard" || item.boards.includes(board)) && matches(item, query);
  const visibleItems = () => items.filter(inScope);

  // ---------- Cards ----------

  function cardBody(item) {
    switch (item.type) {
      case "link":
        return `<p>${esc(item.title)}</p>`;
      case "color":
        return `<span class="hex">${esc(item.content)}</span>`;
      case "image":
        return '<div class="pic" aria-hidden="true"><i class="sun"></i><i class="hill"></i><i class="roofs"></i></div>' +
          `<span class="pill">${esc(item.size)}</span>`;
      default:
        return `<p>${esc(item.content.length > 400 ? item.content.slice(0, 400) : item.content)}</p>`;
    }
  }

  function cardFoot(item) {
    if (item.type === "text") return `<div class="card-foot">${plural([...item.content].length, "character", "characters")}</div>`;
    if (item.type === "link") return `<div class="card-foot"><span class="tile" aria-hidden="true">${esc(host(item.content).charAt(0))}</span>${esc(host(item.content))}</div>`;
    return "";
  }

  function cardNode(item) {
    let node = nodes.get(item.id);
    if (node) return node;
    node = document.createElement("div");
    node.id = item.id;
    node.className = "card t-" + item.type + (item.code ? " is-code" : "");
    node.setAttribute("role", "option");
    node.setAttribute("aria-selected", "false");
    const head = APP_COLOURS[item.app] || "#6B7079";
    node.style.setProperty("--h", head);
    node.style.setProperty("--hfg", textOn(head));
    if (item.type === "color") {
      node.style.setProperty("--swatch", item.content);
      node.style.setProperty("--swfg", textOn(item.content));
    }
    node.innerHTML =
      `<div class="card-head"><span class="card-type">${TYPE_LABELS[item.type]}</span>` +
      `<span class="card-meta">${esc(item.app)}<span class="card-when"> · <time></time></span></span></div>` +
      `<div class="card-body">${cardBody(item)}</div>${cardFoot(item)}<span class="card-num" aria-hidden="true"></span>`;
    nodes.set(item.id, node);
    refreshTime(item, node);
    return node;
  }

  function refreshTime(item, node) {
    const when = relativeTime(item.t);
    const time = $("time", node);
    if (time.textContent !== when) time.textContent = when;
    node.setAttribute("aria-label", `${TYPE_LABELS[item.type]} from ${item.app}, ${when}: ${preview(item)}`);
  }

  const itemById = (id) => items.find((item) => item.id === id);

  function tick() {
    for (const node of list.children) {
      const item = itemById(node.id);
      if (item) refreshTime(item, node);
    }
  }

  function numberCards() {
    [...list.children].forEach((node, i) => { $(".card-num", node).textContent = i < 9 ? String(i + 1) : ""; });
  }

  // ---------- Rendering ----------

  function updateScope(count) {
    const info = BOARDS[board];
    $("[data-scope-mark]").innerHTML = info.colour ? `<span class="dot" style="--dot:${info.colour}"></span>` : CLOCK;
    $("[data-scope-name]").textContent = info.name;
    const q = query.trim();
    $("[data-scope-count]").textContent = q ? `${plural(count, "match", "matches")} for “${q}”` : plural(count, "item", "items");
    empty.hidden = count > 0;
    empty.textContent = q ? "Nothing found. Try another word or filter." : `${info.name} is empty.`;
  }

  function build(shown) {
    list.replaceChildren(...shown.map(cardNode));
    shownIds = shown.map((item) => item.id).join();
    numberCards();
    if (!shown.some((item) => item.id === selected)) select(shown[0] ? shown[0].id : null, { scroll: false });
    else select(selected, { scroll: false });
    updateScope(shown.length);
    tick();
  }

  function render({ fade = true } = {}) {
    const shown = visibleItems();
    const ids = shown.map((item) => item.id).join();
    const generation = ++renderGeneration;
    list.getAnimations().forEach((a) => a.cancel());
    if (ids === shownIds) { updateScope(shown.length); return; }
    if (!fade || !motion() || !list.children.length) { build(shown); return; }
    const fadeOut = list.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 110, easing: "ease-in", fill: "forwards" });
    fadeOut.finished
      .then(() => {
        if (generation !== renderGeneration) return;
        build(shown);
        scroller.scrollLeft = 0;
        fadeOut.cancel();
        list.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 180, easing: "ease-out" });
      })
      .catch(() => {});
  }

  function select(id, { scroll = true } = {}) {
    selected = id;
    for (const node of list.children) node.setAttribute("aria-selected", String(node.id === id));
    if (id) list.setAttribute("aria-activedescendant", id);
    else list.removeAttribute("aria-activedescendant");
    if (scroll && id) reveal(document.getElementById(id));
  }

  function reveal(node) {
    if (!node) return;
    const r = node.getBoundingClientRect(), s = scroller.getBoundingClientRect(), pad = 24;
    const behavior = motion() ? "smooth" : "auto";
    if (r.left < s.left + pad) scroller.scrollBy({ left: r.left - s.left - pad, behavior });
    else if (r.right > s.right - pad) scroller.scrollBy({ left: r.right - s.right + pad, behavior });
  }

  // ---------- Copying ----------

  let suppressCopyEvent = false;

  async function writeClipboard(text) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
      // Older browsers, or a denied permission: copy through a hidden field instead.
      const back = document.activeElement;
      const field = document.createElement("textarea");
      field.value = text;
      field.setAttribute("readonly", "");
      field.style.cssText = "position:fixed;top:0;left:0;opacity:0;pointer-events:none";
      document.body.append(field);
      field.select();
      let ok = false;
      suppressCopyEvent = true;
      try { ok = document.execCommand("copy"); } catch { ok = false; }
      suppressCopyEvent = false;
      field.remove();
      if (back && back.focus) back.focus({ preventScroll: true });
      return ok;
    }
  }

  let toastTimer = 0;
  function toast(main, detail) {
    toastEl.replaceChildren();
    const strong = document.createElement("strong");
    strong.textContent = main;
    toastEl.append(strong);
    if (detail) {
      const span = document.createElement("span");
      span.textContent = detail;
      toastEl.append(" ", span);
    }
    toastEl.classList.add("is-on");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      toastEl.classList.remove("is-on");
      toastTimer = setTimeout(() => toastEl.replaceChildren(), 250);
    }, detail ? 3400 : 1500);
  }

  function announce(text) {
    live.textContent = "";
    requestAnimationFrame(() => { live.textContent = text; });
  }

  async function copyCard(id, { pasted = false } = {}) {
    const item = itemById(id);
    if (!item) return;
    if (item.type === "image") {
      toast("Images copy as images", "In the app, this card puts the picture itself on the clipboard.");
      return;
    }
    const ok = await writeClipboard(item.content);
    if (!ok) { toast("Couldn’t copy", "Your browser blocked it. Select the text and press ⌘C instead."); return; }
    if (pasted) {
      toast("Copied", "In the app, a double-click pastes it straight into the app you were using.");
      const node = document.getElementById(id);
      if (node && motion()) node.animate([{ transform: "none" }, { transform: "translateY(-8px)" }, { transform: "none" }], { duration: 300, easing: "ease-out" });
    } else {
      toast("Copied");
    }
  }

  // ---------- Capturing what the visitor copies ----------

  function asURL(text) {
    if (/\s/.test(text)) return null;
    let candidate = null;
    if (/^https?:\/\/\S+$/i.test(text)) candidate = text;
    else if (/^(www\.)?[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|org|net|io|dev|app|pt|co|uk|me)(\/\S*)?$/i.test(text)) candidate = "https://" + text;
    if (!candidate) return null;
    try {
      const url = new URL(candidate);
      return url.hostname.includes(".") ? url : null;
    } catch { return null; }
  }

  // A link card shows the page's title; this page knows the titles of its own links and falls back to the address.
  function titleFor(url) {
    const path = url.pathname.replace(/\/+$/, "");
    if (url.hostname === "github.com" && /^\/udsy19\/super-paste/i.test(path)) return "udsy19/super-paste: a clipboard manager for your Mac";
    if (url.hostname === "udsy19.github.io" && /^\/super-paste/i.test(path)) return "Super Paste, a clipboard manager for your Mac";
    return url.hostname.replace(/^www\./, "") + (path || "");
  }

  function classify(text, code) {
    const item = { id: "clip-" + ++uid, app: "This page", t: Date.now(), boards: [], type: "text", content: text };
    if (/^#?[0-9a-f]{6}$/i.test(text)) return { ...item, type: "color", content: "#" + text.replace("#", "").toUpperCase() };
    const url = asURL(text);
    if (url) return { ...item, type: "link", content: url.href, title: titleFor(url) };
    item.code = code || /^(curl|git|brew|swift|npm|cd|ssh|open|sudo)\s/.test(text);
    return item;
  }

  function capture(raw, { code = false } = {}) {
    let text = String(raw || "").replace(/\r\n?/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
    if (!text) return;
    if (text.length > 2000) text = text.slice(0, 2000);

    const fresh = classify(text, code);
    // Copying the same thing again moves it to the front instead of adding a duplicate.
    const index = items.findIndex((item) => item.type === fresh.type && item.content === fresh.content);
    let item = fresh;
    if (index >= 0) {
      const [old] = items.splice(index, 1);
      nodes.delete(old.id);
      const oldNode = document.getElementById(old.id);
      if (oldNode) oldNode.dataset.leaving = "true";
      item = { ...fresh, boards: old.boards };
    }
    items.unshift(item);
    for (const dropped of items.splice(MAX_ITEMS)) nodes.delete(dropped.id);

    // Show the whole history again if the current pinboard or search would hide the new card.
    if (!inScope(item)) {
      board = "clipboard";
      query = "";
      search.value = "";
      syncControls();
      build(visibleItems());
      select(item.id, { scroll: false });
      if (motion()) list.animate([{ opacity: 0.4 }, { opacity: 1 }], { duration: 200, easing: "ease-out" });
    } else {
      insertFront(item);
    }

    const label = `${TYPE_LABELS[item.type]} from this page`;
    announce(`Added to the strip: ${label}.`);
    if (document.documentElement.dataset.strip === "collapsed") toast("Added to the strip", "Show the strip to see it.");
  }

  function insertFront(item) {
    scroller.scrollLeft = 0;
    const leaving = list.querySelector('[data-leaving="true"]');
    const before = new Map([...list.children].filter((n) => n !== leaving).map((n) => [n, n.getBoundingClientRect().left]));
    if (leaving) leaving.remove();
    const node = cardNode(item);
    list.prepend(node);
    shownIds = [...list.children].map((n) => n.id).join();
    numberCards();
    select(item.id, { scroll: false });
    updateScope(list.children.length);
    if (!motion()) return;
    before.forEach((left, n) => {
      const dx = left - n.getBoundingClientRect().left;
      if (Math.abs(dx) > 0.5) n.animate([{ transform: `translateX(${dx}px)` }, { transform: "translateX(0)" }], { duration: 320, easing: "cubic-bezier(.2,.8,.2,1)" });
    });
    node.animate(
      [
        { opacity: 0, transform: "translateY(26px) scale(0.92)" },
        { opacity: 1, transform: "translateY(-4px) scale(1.01)", offset: 0.62 },
        { opacity: 1, transform: "none" },
      ],
      { duration: 340, easing: "cubic-bezier(.2,.7,.3,1)" },
    );
  }

  document.addEventListener("copy", () => {
    if (suppressCopyEvent) return;
    const active = document.activeElement;
    let text = "";
    let source = null;
    if (active && /^(INPUT|TEXTAREA)$/.test(active.tagName) && typeof active.selectionStart === "number") {
      text = active.value.slice(active.selectionStart, active.selectionEnd);
      source = active;
    } else {
      const selection = window.getSelection();
      text = selection ? selection.toString() : "";
      const anchor = selection && selection.anchorNode;
      source = anchor ? (anchor.nodeType === 1 ? anchor : anchor.parentElement) : null;
    }
    capture(text, { code: !!(source && source.closest("code, pre, .cmd")) });
  });

  // ---------- Controls ----------

  function syncControls() {
    tabs.forEach((tab) => tab.setAttribute("aria-pressed", String(tab.dataset.board === board)));
    const present = query.trim().split(/\s+/).map(fold);
    tokens.forEach((t) => t.setAttribute("aria-pressed", String(present.includes(fold(t.dataset.token)))));
  }

  tabs.forEach((tab) => tab.addEventListener("click", () => {
    board = tab.dataset.board;
    syncControls();
    render();
  }));

  search.addEventListener("input", () => {
    query = search.value;
    syncControls();
    render();
  });

  tokens.forEach((t) => t.addEventListener("click", () => {
    const token = t.dataset.token;
    const parts = query.trim().split(/\s+/).filter(Boolean);
    const at = parts.findIndex((p) => fold(p) === fold(token));
    if (at >= 0) parts.splice(at, 1); else parts.push(token);
    query = parts.join(" ");
    search.value = query;
    syncControls();
    render();
  }));

  list.addEventListener("click", (e) => {
    const card = e.target.closest(".card");
    if (!card) return;
    select(card.id);
    copyCard(card.id);
  });
  list.addEventListener("dblclick", (e) => {
    const card = e.target.closest(".card");
    if (card) copyCard(card.id, { pasted: true });
  });

  list.addEventListener("keydown", (e) => {
    const cards = [...list.children];
    const modifier = e.metaKey || e.ctrlKey;
    if (e.key === "Meta" || e.key === "Control") { strip.classList.add("show-nums"); return; }
    if (!cards.length) return;
    const at = Math.max(0, cards.findIndex((n) => n.id === selected));
    let next = null;
    if (e.key === "ArrowRight") next = cards[Math.min(cards.length - 1, at + 1)];
    else if (e.key === "ArrowLeft") next = cards[Math.max(0, at - 1)];
    else if (e.key === "Home") next = cards[0];
    else if (e.key === "End") next = cards[cards.length - 1];
    if (next) { e.preventDefault(); select(next.id); return; }
    if (e.key === "Enter" || (modifier && e.key.toLowerCase() === "c")) {
      e.preventDefault();
      if (selected) copyCard(selected);
    } else if (modifier && /^[1-9]$/.test(e.key)) {
      e.preventDefault();
      const card = cards[Number(e.key) - 1];
      if (card) { select(card.id); copyCard(card.id); }
    }
  });
  list.addEventListener("keyup", (e) => { if (e.key === "Meta" || e.key === "Control") strip.classList.remove("show-nums"); });
  list.addEventListener("blur", () => strip.classList.remove("show-nums"));

  // A vertical wheel scrolls the strip sideways, as in the app.
  scroller.addEventListener("wheel", (e) => {
    if (Math.abs(e.deltaY) <= Math.abs(e.deltaX)) return;
    const max = scroller.scrollWidth - scroller.clientWidth;
    if (max <= 0 || (e.deltaY < 0 && scroller.scrollLeft <= 0) || (e.deltaY > 0 && scroller.scrollLeft >= max)) return;
    scroller.scrollLeft += e.deltaY;
    e.preventDefault();
  }, { passive: false });

  const toggle = $("[data-strip-toggle]");
  const stripBody = $("#strip-body");
  function setCollapsed(collapsed) {
    document.documentElement.dataset.strip = collapsed ? "collapsed" : "open";
    toggle.setAttribute("aria-expanded", String(!collapsed));
    $("[data-toggle-label]").textContent = collapsed ? "Show" : "Hide";
    stripBody.inert = collapsed;
  }
  toggle.addEventListener("click", () => setCollapsed(document.documentElement.dataset.strip !== "collapsed"));

  $$("[data-copy]").forEach((chip) => chip.addEventListener("click", async () => {
    const text = chip.dataset.copy;
    if (!(await writeClipboard(text))) { toast("Couldn’t copy", "Your browser blocked it. Select the text and press ⌘C instead."); return; }
    capture(text);
    chip.classList.add("is-copied");
    setTimeout(() => chip.classList.remove("is-copied"), 1600);
  }));

  $$("[data-copy-cmd]").forEach((button) => button.addEventListener("click", async () => {
    const text = $("code", button.closest("[data-cmd]")).textContent;
    if (!(await writeClipboard(text))) { toast("Couldn’t copy", "Your browser blocked it. Select the command and press ⌘C instead."); return; }
    capture(text, { code: true });
    button.textContent = "Copied";
    setTimeout(() => { button.textContent = "Copy"; }, 1600);
  }));

  // ---------- Paste Stack demo ----------

  const STACK = [
    { app: "Notes", text: "Sam Ortega" },
    { app: "Mail", text: "Rua das Flores 28, 2º esq." },
    { app: "Mail", text: "1200-195 Lisboa, Portugal" },
  ];
  const stackList = $("[data-stack-list]");
  const stackCount = $("[data-stack-count]");
  const target = $("[data-target]");
  const caret = $(".caret", target);
  const addButton = $("[data-stack-add]");
  const pasteButton = $("[data-stack-paste]");
  const resetButton = $("[data-stack-reset]");
  let queue = [];

  function stackCard(entry) {
    const li = document.createElement("li");
    li.className = "card t-text";
    const head = APP_COLOURS[entry.app];
    li.style.setProperty("--h", head);
    li.style.setProperty("--hfg", textOn(head));
    li.innerHTML = `<div class="card-head"><span class="card-meta">${esc(entry.app)}</span></div><div class="card-body"><p>${esc(entry.text)}</p></div>`;
    return li;
  }

  function updateStack() {
    stackCount.textContent = queue.length ? plural(queue.length, "item", "items") : "Empty";
    [...stackList.children].forEach((li, i) => li.classList.toggle("is-next", i === 0));
    pasteButton.disabled = queue.length === 0;
  }

  addButton.addEventListener("click", () => {
    queue = STACK.slice();
    stackList.replaceChildren(...queue.map(stackCard));
    $$(".line", target).forEach((line) => line.remove());
    if (motion()) {
      [...stackList.children].forEach((li, i) => li.animate(
        [{ opacity: 0, transform: "translateY(18px) scale(0.94)" }, { opacity: 1, transform: "translateY(-3px)", offset: 0.62 }, { opacity: 1, transform: "none" }],
        { duration: 320, delay: i * 90, easing: "cubic-bezier(.2,.7,.3,1)", fill: "backwards" },
      ));
    }
    addButton.disabled = true;
    resetButton.hidden = false;
    updateStack();
    pasteButton.focus();
    announce("Three items in the Paste Stack.");
  });

  pasteButton.addEventListener("click", () => {
    const entry = queue.shift();
    if (!entry) return;
    const first = stackList.firstElementChild;
    const finish = () => { first.remove(); updateStack(); };
    if (first && motion()) {
      first.classList.remove("is-next");
      first.animate([{ opacity: 1, transform: "none" }, { opacity: 0, transform: "translateX(24px)" }], { duration: 180, easing: "ease-in", fill: "forwards" }).finished.then(finish, finish);
    } else if (first) {
      finish();
    }
    const line = document.createElement("span");
    line.className = "line is-new";
    line.textContent = entry.text;
    target.insertBefore(line, caret);
    pasteButton.disabled = queue.length === 0;
    if (!queue.length) resetButton.focus();
    announce(`Pasted ${entry.text}.`);
  });

  resetButton.addEventListener("click", () => {
    queue = [];
    stackList.replaceChildren();
    $$(".line", target).forEach((line) => line.remove());
    addButton.disabled = false;
    resetButton.hidden = true;
    updateStack();
    addButton.focus();
  });

  // ---------- Start ----------

  strip.hidden = false;
  setCollapsed(false);
  syncControls();
  build(visibleItems());
  setInterval(tick, 15e3);
})();
