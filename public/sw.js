const CACHE_PREFIX = 'pongo-';
const STATIC_CACHE = 'pongo-static-v4';
const ASSET_CACHE = 'pongo-assets-v4';
const OFFLINE_ASSETS = [
  '/offline.html',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/pongo.webp',
];

self.addEventListener('install', (event) => {
  // Do not skip waiting: an update activates only after older pages close, so
  // an open match can keep using the exact JS/CSS version it started with.
  event.waitUntil(caches.open(STATIC_CACHE).then((cache) => cache.addAll(OFFLINE_ASSETS)));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys
        .filter((key) => key.startsWith(CACHE_PREFIX) && key !== STATIC_CACHE && key !== ASSET_CACHE)
        .map((key) => caches.delete(key))))
      .then(() => self.registration.navigationPreload?.enable())
      .then(() => self.clients.claim()),
  );
});

async function cacheFirst(request) {
  const cache = await caches.open(ASSET_CACHE);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response.ok) await cache.put(request, response.clone());
  return response;
}

async function staleWhileRevalidate(event) {
  const cache = await caches.open(STATIC_CACHE);
  const cached = await cache.match(event.request);
  const update = fetch(event.request).then((response) => {
    if (response.ok) return cache.put(event.request, response.clone()).then(() => response);
    return response;
  });
  if (cached) {
    event.waitUntil(update.catch(() => undefined));
    return cached;
  }
  return update;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    // Authenticated HTML and RSC data are never cached. Navigation preload
    // begins the request while the worker starts and falls back only offline.
    event.respondWith((async () => {
      try { return (await event.preloadResponse) || await fetch(request); }
      catch { return (await caches.match('/offline.html')) || Response.error(); }
    })());
    return;
  }

  if (url.pathname.startsWith('/api/') || url.pathname.startsWith('/auth/')) return;

  // Next build assets are content-hashed and safe to keep cache-first.
  if (url.pathname.startsWith('/_next/static/')) {
    event.respondWith(cacheFirst(request));
    return;
  }

  if (url.pathname === '/pongo.webp' || url.pathname.startsWith('/icons/')) {
    event.respondWith(staleWhileRevalidate(event));
  }
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = new URL(event.notification.data?.url || '/queue', self.location.origin).href;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clients) => {
      const existing = clients.find((client) => client.url.startsWith(self.location.origin));
      if (existing) {
        existing.navigate(targetUrl);
        return existing.focus();
      }
      return self.clients.openWindow(targetUrl);
    }),
  );
});
