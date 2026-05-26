import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './e2e/tests',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? [['github'], ['list']] : 'list',
  timeout: 30_000,

  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  webServer: {
    command: 'bun dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
    timeout: 60_000,
    // Point the app's API calls to port 9999 — a port that Vite's proxy does NOT
    // forward. Playwright's page.route() intercepts those browser-level requests
    // before any TCP connection is attempted. Without this, Vite's server-side
    // proxy (/api → localhost:8080) races against Playwright's CDP interception
    // and wins, causing ECONNREFUSED errors in the webServer log.
    env: {
      VITE_API_BASE_URL: process.env.VITE_API_BASE_URL ?? 'http://localhost:9999',
    },
  },
})
