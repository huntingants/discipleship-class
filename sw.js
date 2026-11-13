// Keeps the app opening when the connection is poor.
// Lessons and Bible verses are in data/*.json; each is saved here the first time the app loads it.
const V = "dc-v8";
const CORE = ["./", "index.html", "config.js", "supabase.js", "591.supabase.js", "manifest.webmanifest", "icons/icon-192.png", "icons/icon-512.png", "icons/apple-touch-icon.png", "ss4-latin.woff2", "ss4-latin-i.woff2"];
self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(V).then((c) => c.addAll(CORE)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== V).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
function fromNetwork(r) {
  return fetch(r).then((n) => { if (n.ok) { const cp = n.clone(); caches.open(V).then((c) => c.put(r, cp)); } return n; });
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
