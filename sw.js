// Keeps the app opening when the connection is poor. Lessons and verses are inside index.html.
const V = "dc-v7";
const CORE = ["./", "index.html", "config.js", "supabase.js", "591.supabase.js", "manifest.webmanifest", "icons/icon-192.png", "icons/icon-512.png", "icons/apple-touch-icon.png", "ss4-latin.woff2", "ss4-latin-i.woff2"];
self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(V).then((c) => c.addAll(CORE)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((ks) => Promise.all(ks.filter((k) => k !== V).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("push", (e) => {
  if (!e.data) return;
  try {
    const d = e.data.json();
    e.waitUntil(
      self.registration.showNotification(d.title || "Discipleship Class", {
        body: d.body || "",
        icon: "icons/icon-192.png",
        badge: "icons/icon-192.png",
        data: { url: d.url || "/" }
      })
    );
  } catch (err) {}
});
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const url = e.notification.data && e.notification.data.url ? e.notification.data.url : "/";
  e.waitUntil(clients.matchAll({ type: "window" }).then((cl) => {
    for (const c of cl) { if (c.url.includes(self.location.origin) && "focus" in c) return c.focus(); }
    return clients.openWindow(url);
  }));
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
