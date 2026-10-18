// Replaces Flutter's old offline-first service worker on returning devices.
// deploy_web.bat copies this over the empty flutter_service_worker.js that
// `--pwa-strategy=none` emits. Browsers re-check that script on navigation;
// this one takes over at once, wipes the stale app cache, unregisters
// itself and reloads open tabs onto the current build from the network.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    clients.forEach((c) => c.navigate(c.url));
  })());
});
