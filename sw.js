// ═══════════════════════════════════════════════════════════════════════════════
//  BH_Sim Service Worker — Cache statique pour PWA
//
//  Cache-first pour les assets statiques (HTML, CSS, JS, shaders, images).
//  Network-first pour version.json (toujours à jour).
// ═══════════════════════════════════════════════════════════════════════════════
'use strict';

const CACHE_NAME = 'bh-sim-v1.5.1';
const STATIC_ASSETS = [
    '/',
    'index.html',
    'main.js',
    'style.css',
    'shaders/vertex.glsl',
    'shaders/fragment.glsl',
    'icon-192.png',
    'icon-512.png',
    'manifest.json',
    'screenshot.png',
];

// ── Install ──────────────────────────────────────────────────────────────────
// Met en cache tous les assets statiques au premier chargement.

self.addEventListener('install', (event) => {
    event.waitUntil(
        caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
    );
    // Active le SW immédiatement (pas de wait pour l'ancienne version)
    self.skipWaiting();
});

// ── Activate ─────────────────────────────────────────────────────────────────
// Supprime les anciens caches pour liberer de l'espace.

self.addEventListener('activate', (event) => {
    event.waitUntil(
        caches.keys().then((names) =>
            Promise.all(
                names
                    .filter((name) => name !== CACHE_NAME)
                    .map((name) => caches.delete(name))
            )
        )
    );
    // Prend le contrôle des pages ouvertes immédiatement
    self.clients.claim();
});

// ── Fetch ────────────────────────────────────────────────────────────────────
// Cache-first pour les assets statiques, network-first pour version.json.

self.addEventListener('fetch', (event) => {
    const url = new URL(event.request.url);

    // version.json → network-first (toujours à jour)
    if (url.pathname.endsWith('version.json')) {
        event.respondWith(
            fetch(event.request)
                .then((response) => {
                    const clone = response.clone();
                    caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
                    return response;
                })
                .catch(() => caches.match(event.request))
        );
        return;
    }

    // Tout le reste → cache-first
    event.respondWith(
        caches.match(event.request).then((cached) => {
            if (cached) return cached;
            return fetch(event.request).then((response) => {
                // Ne met en cache que les réponses valides (type opaque excluded)
                if (!response || response.status !== 200 || response.type !== 'basic') {
                    return response;
                }
                const clone = response.clone();
                caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
                return response;
            });
        })
    );
});
