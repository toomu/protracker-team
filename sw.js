// Lets the team app open without a connection. The app's own files are fetched fresh when online
// (so updates arrive at once) and kept as a fallback; the sign-in library and fonts are kept after
// their first load. Database and sign-in requests (supabase.co) are never touched.
const CACHE = "team-v2";
const SHELL = ["./", "manifest.webmanifest", "logo.png", "icon-192.png", "favicon.png",
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.js"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).catch(() => {}).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin === location.origin) {
    // Network first; the saved copy when offline. Every page address (?demo, #publish=…) falls back to the app.
    e.respondWith(fetch(req).then(res => {
      if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req.mode === "navigate" ? "./" : req, copy)); }
      return res;
    }).catch(() => caches.match(req.mode === "navigate" ? "./" : req, { ignoreSearch: true })
      .then(r => r || Response.error())));
    return;
  }
  if (["cdn.jsdelivr.net", "fonts.googleapis.com", "fonts.gstatic.com"].includes(url.hostname)) {
    e.respondWith(caches.match(req).then(hit => hit || fetch(req).then(res => {
      if (res.ok || res.type === "opaque") { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }
      return res;
    })));
  }
});

// Notifications sent by the push function when new tasks are published to this person.
self.addEventListener("push", (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { body: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(d.title || "ProTracker Team", {
    body: d.body || "", icon: "icon-192.png", data: { url: "./" },
  }));
});
// Tapping one opens the app (or brings an open window forward, which then reloads its list).
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
    const open = list.find(c => new URL(c.url).pathname.startsWith(new URL(self.registration.scope).pathname));
    return open ? open.focus() : self.clients.openWindow(new URL("./", self.registration.scope).href);
  }));
});
