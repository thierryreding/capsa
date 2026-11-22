import { svelte } from '@sveltejs/vite-plugin-svelte';
import { defineConfig } from 'vitest/config';

// During development the API runs in the local pod (deploy/local/pod.sh up);
// /api is proxied so that app and API share one origin, as in production.
const api = process.env.CAPSA_API ?? 'http://capsa.localhost:8080';

export default defineConfig({
  plugins: [svelte()],
  server: {
    proxy: { '/api': { target: api, changeOrigin: true } },
  },
  test: {
    include: ['src/**/*.test.ts'],
    environment: 'node',
  },
});
