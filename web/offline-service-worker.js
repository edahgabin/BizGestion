const CACHE_NAME = 'bizgestion-offline-v6';
const NETWORK_FIRST_FILES = new Set([
  './index.html',
  './flutter_bootstrap.js',
  './flutter.js',
  './main.dart.js',
  './version.json',
  './manifest.json',
].map((path) => new URL(path, self.registration.scope).pathname));
const OLD_CACHE_PREFIX = 'bizgestion-offline-';

const CORE_FILES = [
  './',
  './index.html',
  './flutter_bootstrap.js',
  './flutter.js',
  './main.dart.js',
  './manifest.json',
  './chariow-checkout.html',
];

const SUPPORT_FILES = [
  './version.json',
  './assets/AssetManifest.bin',
  './assets/AssetManifest.bin.json',
  './assets/FontManifest.json',
  './favicon.png',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
  './icons/Icon-maskable-192.png',
  './icons/Icon-maskable-512.png',
  './assets/assets/branding/bizgestion-logo.png',
  './assets/fonts/MaterialIcons-Regular.otf',
  './assets/packages/cupertino_icons/assets/CupertinoIcons.ttf',
  './canvaskit/canvaskit.js',
  './canvaskit/canvaskit.wasm',
  './canvaskit/chromium/canvaskit.js',
  './canvaskit/chromium/canvaskit.wasm',
  './canvaskit/webparagraph/canvaskit.js',
  './canvaskit/webparagraph/canvaskit.wasm',
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(CORE_FILES.map((path) => new URL(path, self.registration.scope).toString()));
    await Promise.allSettled(SUPPORT_FILES.map(async (path) => {
      const request = new Request(new URL(path, self.registration.scope), {
        cache: 'reload',
      });
      const response = await fetch(request);
      if (response.ok && response.type === 'basic') {
        await cache.put(request, response);
      }
    }));
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names
      .filter((name) => name.startsWith(OLD_CACHE_PREFIX) && name !== CACHE_NAME)
      .map((name) => caches.delete(name)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  // Never cache authentication, database, payment, or other third-party traffic.
  if (url.origin !== self.location.origin) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE_NAME);
    const cached = await cache.match(request, { ignoreSearch: true });

    if (request.mode === 'navigate' || NETWORK_FIRST_FILES.has(url.pathname)) {
      try {
        const response = await fetch(request);
        if (response.ok && response.type === 'basic') {
          await cache.put(request, response.clone());
        }
        return response;
      } catch (_) {
        const fallback = cached || await cache.match(new URL('./index.html', self.registration.scope).toString());
        return fallback || new Response('', { status: 503, statusText: 'Offline resource unavailable' });
      }
    }

    const network = fetch(request).then((response) => {
      if (response.ok && response.type === 'basic') {
        event.waitUntil(cache.put(request, response.clone()));
      }
      return response;
    });
    if (cached) {
      // Refresh the cache in the background when online, but don't delay the UI.
      event.waitUntil(network.catch(() => {}));
      return cached;
    }
    try {
      return await network;
    } catch (_) {
      return new Response('', { status: 503, statusText: 'Offline resource unavailable' });
    }
  })());
});
