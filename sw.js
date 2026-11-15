// Keeps the app opening when the connection is poor. Lessons and verses are inside index.html.
const V = "dc-v7";
const CORE = ["./", "index.html", "config.js", "supabase.js", "591.supabase.js", "manifest.webmanifest", "icons/icon-192.png", "icons/icon-512.png", "icons/apple-touch-icon.png", "ss4-latin.woff2", "ss4-latin-i.woff2"];
self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(V).then((c) => c.addAll(CORE)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== V).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const r = e.request;
  if (r.method !== "GET") return;
  const u = new URL(r.url);
  if (u.origin !== location.origin) return;
  // our own files: network first so updates arrive at once, cache when offline
  e.respondWith(
    fetch(r).then((n) => { if (n.ok) { const cp = n.clone(); caches.open(V).then((c) => c.put(r, cp)); } return n; })
      .catch(() => caches.match(r).then((h) => h || caches.match("index.html")))
  );
});
