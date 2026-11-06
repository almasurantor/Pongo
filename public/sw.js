const CACHE_PREFIXES = ['pongo-', 'beaver-smash-'];
const SHELL_CACHE = 'pongo-shell-v5';
const OFFLINE_ASSETS = [
  '/offline.html',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(SHELL_CACHE);
    // Keep the previous worker active if the essential fallback cannot be
    // fetched; activating an empty shell would make offline recovery worse.
    await cache.add('/offline.html');
    // A temporarily unavailable icon must not prevent a worker update from
    // installing and repairing an existing Home Screen app.
    await Promise.allSettled(OFFLINE_ASSETS.slice(1).map((asset) => cache.add(asset)));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys
      .filter((key) => key !== SHELL_CACHE && CACHE_PREFIXES.some((prefix) => key.startsWith(prefix)))
      .map((key) => caches.delete(key)));
    await self.clients.claim();
  })());
});

self.addEventListener('message', (event) => {
  if (event.data?.type === 'SKIP_WAITING') void self.skipWaiting();
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    // Authenticated HTML and RSC data are never cached. A launch always asks
    // the current deployment for its current build, with a static explanation
    // used only when the network request itself cannot be made.
    event.respondWith((async () => {
      try { return await fetch(request, { cache: 'no-store' }); }
      catch {
        const shell = await caches.open(SHELL_CACHE);
        return (await shell.match('/offline.html')) || Response.error();
      }
    })());
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
