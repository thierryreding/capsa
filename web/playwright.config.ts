import { defineConfig, devices } from '@playwright/test';

const apiPort = 8765;
const webPort = 5180;

export default defineConfig({
  testDir: 'e2e',
  timeout: 60_000,
  use: { baseURL: `http://localhost:${webPort}`, trace: 'retain-on-failure' },
  projects: [
    { name: 'phone', use: { ...devices['Pixel 7'] } },
  ],
  webServer: [
    {
      command: 'e2e/api.sh',
      url: `http://127.0.0.1:${apiPort}/api/v1/health`,
      env: { CAPSA_E2E_API_PORT: String(apiPort) },
      reuseExistingServer: false,
    },
    {
      command: `npx vite --port ${webPort} --strictPort`,
      url: `http://localhost:${webPort}`,
      env: { CAPSA_API: `http://127.0.0.1:${apiPort}` },
      reuseExistingServer: false,
    },
  ],
});
