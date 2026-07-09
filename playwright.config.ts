import { defineConfig, devices } from '@playwright/test'
import path from 'path'
import { fileURLToPath } from 'url'

const kitRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)))

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  timeout: 20_000,
  expect: {
    timeout: 5_000,
  },
  reporter: process.env.CI
    ? [['blob']]
    : [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: process.env.PLAYWRIGHT_BASE_URL || 'http://127.0.0.1:8000',
    actionTimeout: 5_000,
    navigationTimeout: 15_000,
    trace: process.env.PLAYWRIGHT_TRACE === 'on' ? 'retain-on-failure' : 'off',
    screenshot: 'only-on-failure',
    video: 'off',
    ignoreHTTPSErrors: true,
  },
  webServer: process.env.PLAYWRIGHT_BASE_URL ? undefined : {
    command: 'PHP_CLI_SERVER_WORKERS=10 php artisan serve --host=127.0.0.1 --port=8000 --no-reload',
    cwd: process.env.PROJECT_ROOT,
    url: 'http://127.0.0.1:8000',
    reuseExistingServer: true,
    timeout: 60_000,
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
  outputDir: path.join(kitRoot, 'test-results'),
})
