// Keeps the app opening when the connection is poor.
// Lessons and Bible verses are in data/*.json; each is saved here the first time the app loads it.
const V = "dc-v9";

// notifications from the class (sent by the "notify" function in Supabase)
self.addEventListener("push", (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (x) { d = { body: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(d.title || "Discipleship Class", {
    body: d.body || "", tag: d.tag || "class", renotify: true,
    icon: "icons/icon-192.png", badge: "icons/icon-192.png", data: { url: d.url || "" }
  }));
});
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const target = new URL("./" + ((e.notification.data && e.notification.data.url) || ""), self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
    for (const c of list) { if (c.url.startsWith(self.registration.scope) && "focus" in c) { c.navigate(target).catch(() => {}); return c.focus(); } }
    return self.clients.openWindow(target);
  }));
});
const CORE = ["./", "index.html", "config.js", "supabase.js", "591.supabase.js", "manifest.webmanifest", "icons/icon-192.png", "icons/icon-512.png", "icons/apple-touch-icon.png", "ss4-latin.woff2", "ss4-latin-i.woff2"];
self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(V).then((c) => c.addAll(CORE)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== V).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
function fromNetwork(r) {
  // always ask the server whether a file changed (a quick "not modified" if not), so updates are never held back by the browser's own cache
  const req = r.mode === "navigate" ? r : new Request(r, { cache: "no-cache" });
  return fetch(req).then((n) => { if (n.ok) { const cp = n.clone(); caches.open(V).then((c) => c.put(r, cp)); } return n; });
}
self.addEventListener("fetch", (e) => {
  const r = e.request;
  if (r.method !== "GET") return;
  const u = new URL(r.url);
  if (u.origin !== location.origin) return;
  if (u.pathname.includes("/data/")) {
    // lessons and verses: use the saved copy at once if there is one, and refresh it in the background
    e.respondWith(caches.match(r).then((hit) => {
      const net = fromNetwork(r);
      if (hit) { e.waitUntil(net.catch(() => {})); return hit; }
      return net;
    }));
    return;
  }
  // the app's own files: network first so updates arrive at once, saved copy when offline
  e.respondWith(
    fromNetwork(r).catch(() => caches.match(r).then((h) => h || (r.mode === "navigate" ? caches.match("index.html") : Response.error())))
  );
});
