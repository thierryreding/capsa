import { svelte } from '@sveltejs/vite-plugin-svelte';
import { VitePWA } from 'vite-plugin-pwa';
import { defineConfig } from 'vitest/config';
import pkg from './package.json' with { type: 'json' };

// During development the API runs in the local pod (deploy/local/pod.sh up);
// /api is proxied so that app and API share one origin, as in production.
const api = process.env.CAPSA_API ?? 'http://capsa.localhost:8080';

export default defineConfig({
  define: { __APP_VERSION__: JSON.stringify(pkg.version) },
  plugins: [
    svelte(),
    VitePWA({
      // A new version is offered in the overview, never forced mid-session.
      registerType: 'prompt',
      injectRegister: false,
      // Icons and <head> links are generated from public/icon.svg (pwa-assets.config.ts).
      pwaAssets: { config: true, overrideManifestIcons: true },
      manifest: {
        name: 'Capsa',
        short_name: 'Capsa',
        description: 'Vokabeln lernen, auch offline',
        lang: 'de',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        orientation: 'portrait',
        background_color: '#f4f1ea',
        theme_color: '#1d4e5f',
      },
      workbox: {
        // The app shell is precached; profiles and answers live in IndexedDB.
        // No 'webmanifest' here: the plugin adds the manifest itself, and a second entry
        // with another revision makes Workbox abort the install (nothing gets cached).
        globPatterns: ['**/*.{js,css,html,svg,png,ico}'],
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/api\//],
        cleanupOutdatedCaches: true,
      },
    }),
  ],
  server: {
    proxy: { '/api': { target: api, changeOrigin: true } },
  },
  test: {
    include: ['src/**/*.test.ts'],
    environment: 'node',
  },
});
