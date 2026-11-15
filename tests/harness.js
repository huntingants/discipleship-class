// Test harness: runs the real app code from index.html in Node, with a fake Supabase, a fake page
// and the real data/*.json files. Nothing is sent to the real database.
const fs = require("fs"), vm = require("vm"), path = require("path");
const ROOT = path.join(__dirname, "..");

function appScript(html) {
  let a = html.indexOf("<script>\n(function"); if (a < 0) a = html.indexOf("<script>\r\n(function");
  if (a < 0) throw new Error("could not find the app script in index.html");
  const start = html.indexOf("\n", a) + 1;
  return html.slice(start, html.indexOf("</script>", start));
}
function jsonScript(html, id) {
  const open = '<script type="application/json" id="' + id + '">', a = html.indexOf(open);
  return a < 0 ? null : html.slice(a + open.length, html.indexOf("</script>", a));
}
// a stand-in for any page element: remembers innerHTML/textContent, ignores everything else
function el() {
  const t = { innerHTML: "", textContent: "", value: "", style: { setProperty() {} }, dataset: {}, children: [],
    classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } } };
  return new Proxy(t, { get(o, k) { if (k in o) return o[k]; if (k === "then") return undefined; return () => el(); } });
}

/**
 * Start the app.
 *  server:   { tableName: [rows] } that the fake database returns
 *  local:    { key: value } already in the phone's storage
 *  hash:     the page address after #
 *  rpc:      { functionName: result } for database functions
 *  uid:      the signed-in person (or signedIn: false)
 */
function start(opt) {
  const html = fs.readFileSync(path.join(ROOT, "index.html"), "utf8");
  const server = opt.server || {}, uid = opt.uid || "u1";
  const writes = [], rpcCalls = [], rpcs = [], winOn = {}, signOuts = [], fetched = [], invokes = [], subs = [], listeners = [], counts = {};

  function builder(table) {
    counts[table] = (counts[table] || 0) + 1;
    const st = { op: "select", filters: [], payload: null, single: false };
    const b = {
      select() { return b; }, eq(k, v) { st.filters.push([k, v]); return b; }, neq() { return b; },
      in(k, v) { st.filters.push([k, v, "in"]); return b; }, gte() { return b; }, limit() { return b; },
      order() { return b; }, maybeSingle() { st.single = true; return b; }, single() { st.single = true; return b; },
      insert(p) { st.op = "insert"; st.payload = p; return b; }, upsert(p) { st.op = "upsert"; st.payload = p; return b; },
      update(p) { st.op = "update"; st.payload = p; return b; }, delete() { st.op = "delete"; return b; },
      then(res, rej) {
        let out;
        if (st.op !== "select") { writes.push({ table, op: st.op, payload: st.payload, filters: st.filters }); out = { data: null, error: null }; }
        else {
          const rows = (server[table] || []).filter((r) => st.filters.every(([k, v, how]) => how === "in" ? v.includes(r[k]) : (r[k] === undefined || r[k] === v)));
          out = { data: st.single ? rows[0] || null : rows, error: null };
        }
        return Promise.resolve(out).then(res, rej);
      }
    };
    return b;
  }
  const rpcDefaults = { my_attendance: { mine: [], held: [] }, my_groups: [], class_roster: [], is_app_admin: false };
  const sb = {
    from: builder,
    rpc: (n, a) => { rpcCalls.push(n); rpcs.push({ name: n, args: a }); const err = opt.rpcError && opt.rpcError[n]; return Promise.resolve({ data: opt.rpc && n in opt.rpc ? opt.rpc[n] : (n in rpcDefaults ? rpcDefaults[n] : null), error: err ? { message: err } : null }); },
    auth: {
      getSession: () => Promise.resolve({ data: { session: opt.signedIn === false ? null : { user: { id: uid, email: "user@example.test" }, access_token: "test" } } }),
      onAuthStateChange() {}, signOut: () => { signOuts.push(1); return Promise.resolve({}); }
    },
    functions: { invoke: (n, o) => { invokes.push(o.body.kind); return Promise.resolve({ data: opt.invokeResult || { sent: 2 } }); } },
    realtime: { setAuth() {} },
    channel() {
      const ch = { on(type, o, cb) { subs.push(o.table + (o.filter ? "[" + o.filter + "]" : "")); listeners.push([o.table, cb]); return ch; },
        subscribe(cb) { setTimeout(() => cb("SUBSCRIBED"), 10); return ch; } };
      return ch;
    },
    removeChannel() {}
  };

  const ls = new Map(Object.entries(opt.local || {}));
  const storage = { getItem: (k) => (ls.has(k) ? ls.get(k) : null), setItem: (k, v) => ls.set(k, String(v)), removeItem: (k) => ls.delete(k), key: (i) => Array.from(ls.keys())[i] || null, get length() { return ls.size; } };
  const els = {}, on = {};
  const ctx = {
    console, setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {}, Promise, JSON, Math, Date, Object, Array, String, Number,
    RegExp, Error, TypeError, Proxy, Map, Set, URL, Uint8Array, atob: (s) => Buffer.from(s, "base64").toString("binary"), Blob: function () {},
    localStorage: storage, sessionStorage: storage,
    location: { hash: opt.hash ? "#" + opt.hash : "", pathname: "/", search: "", origin: "http://localhost", host: "localhost" },
    history: { replaceState() {} }, navigator: { onLine: true, userAgent: "node", maxTouchPoints: 0 },
    matchMedia: () => ({ matches: false, addEventListener() {}, addListener() {} }),
    scrollTo() {}, addEventListener(type, f) { (winOn[type] = winOn[type] || []).push(f); }, removeEventListener() {}, requestAnimationFrame: (f) => setTimeout(f, 0),
    crypto: { randomUUID: () => "id-" + Math.random().toString(36).slice(2) },
    fetch: (p) => {
      fetched.push(p);
      const fp = path.join(ROOT, p), blocked = opt.blockFetch && opt.blockFetch.test(p);
      return !blocked && fs.existsSync(fp)
        ? Promise.resolve({ ok: true, json: () => Promise.resolve(JSON.parse(fs.readFileSync(fp, "utf8"))) })
        : Promise.reject(new TypeError("Failed to fetch"));
    },
    document: {
      getElementById: (id) => { const j = jsonScript(html, id); return j !== null ? { textContent: j } : (els[id] = els[id] || el()); },
      querySelector: () => null, querySelectorAll: () => [], createElement: () => el(),
      addEventListener(type, f) { on[type] = f; },
      body: el(), documentElement: el(), hidden: false, head: el(), activeElement: null
    }
  };
  ctx.window = ctx; ctx.self = ctx; ctx.supabase = { createClient: () => sb };
  // opt.push = { subKey: "<base64url key the phone signed up with>" | null }: a phone that supports notifications
  const pushLog = [];
  if (opt.push) {
    const KEY = "BNbtNPFAIURJ-G0nkRshn8kkW-SjFDGSH-GK-8ts2xfINVQpw-zKdy2-mtKmBWPGkwpMgL0VQvnoDKCN8ScXEjc";
    const bytes = (k) => Uint8Array.from(Buffer.from(k.replace(/-/g, "+").replace(/_/g, "/"), "base64")).buffer;
    let sub = opt.push.subKey ? { endpoint: "https://fcm.googleapis.com/x", options: { applicationServerKey: bytes(opt.push.subKey) },
      toJSON: () => ({ endpoint: "https://fcm.googleapis.com/x", keys: { p256dh: "p", auth: "a" } }), unsubscribe: () => { pushLog.push("unsubscribe"); sub = null; return Promise.resolve(true); } } : null;
    const reg = { pushManager: { getSubscription: () => Promise.resolve(sub), subscribe: (o) => { pushLog.push("subscribe"); sub = { endpoint: "https://fcm.googleapis.com/new", options: o, toJSON: () => ({ endpoint: "https://fcm.googleapis.com/new", keys: { p256dh: "p", auth: "a" } }), unsubscribe: () => Promise.resolve(true) }; return Promise.resolve(sub); } } };
    ctx.DC_CONFIG = { url: "https://x.supabase.co", key: "k", push: KEY };
    ctx.PushManager = function () {}; ctx.Notification = { permission: "granted", requestPermission: () => Promise.resolve("granted") };
    ctx.navigator.serviceWorker = { ready: Promise.resolve(reg), register: () => Promise.resolve(reg), addEventListener() {}, controller: null };
  }
  vm.createContext(ctx);
  vm.runInContext(appScript(html), ctx, { filename: "index.html (app script)" });

  return {
    writes, rpcCalls, rpcs, signOuts, fetched, invokes, subs, counts, storage, ls,
    pushLog,
    fire(type, ev) { (winOn[type] || []).forEach((f) => f(ev)); },
    page: () => (els.app ? els.app.innerHTML : ""),
    toast: () => (els.toast ? els.toast.textContent : ""),
    click(act, attrs) { on.click({ target: { closest: (sel) => sel === "[data-act]" ? { getAttribute: (k) => k === "data-act" ? act : (attrs || {})[k] } : null }, preventDefault() {} }); },
    type(bind, value) { on.input({ target: { getAttribute: (k) => (k === "data-bind" ? bind : null), value } }); },
    emit(table, payload) { listeners.filter(([t]) => t === table).forEach(([, cb]) => cb(payload)); }
  };
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));
module.exports = { start, wait };
