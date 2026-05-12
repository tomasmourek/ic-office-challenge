// IC Office Challenge — service worker pro PWA install + offline cache.
// Verzování přes konstantu CACHE_VERSION — při změně CSS/JS bumpni číslo,
// abys donutil klienty stáhnout novou verzi.

const CACHE_VERSION = 'ic-office-challenge-v1';
const APP_SHELL = [
  '/',
  '/index.html',
  '/leaderboard.html',
  '/qa.html',
  '/favicon.png',
  '/site.webmanifest'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then(cache => cache.addAll(APP_SHELL)).catch(err => {
      // Pokud nějaký z app shell souborů nelze cachovat (např. index.html neexistuje
      // přes /, ale jen jako /index.html), nezablokuj install — fetch handler stejně
      // pracuje s network-first fallback.
      console.warn('SW install: některé assety se nepodařilo cachovat:', err);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  // Odstranit staré verze cache (po bumpu CACHE_VERSION)
  event.waitUntil(
    caches.keys().then(keys => Promise.all(
      keys.filter(k => k !== CACHE_VERSION).map(k => caches.delete(k))
    ))
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  // Cache jen GET HTML/CSS/JS/Image požadavky na stejnou origin.
  // Supabase API, CDN knihovny atd. necháváme bez kešování — vždy live.
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  // Network-first pro HTML (aby uživatel viděl čerstvou verzi), cache-first pro statiku.
  const isHtml = req.headers.get('accept') && req.headers.get('accept').includes('text/html');

  if (isHtml) {
    event.respondWith(
      fetch(req).then(res => {
        const copy = res.clone();
        caches.open(CACHE_VERSION).then(c => c.put(req, copy));
        return res;
      }).catch(() => caches.match(req).then(cached => cached || caches.match('/index.html')))
    );
  } else {
    event.respondWith(
      caches.match(req).then(cached => cached || fetch(req).then(res => {
        const copy = res.clone();
        caches.open(CACHE_VERSION).then(c => c.put(req, copy));
        return res;
      }))
    );
  }
});
