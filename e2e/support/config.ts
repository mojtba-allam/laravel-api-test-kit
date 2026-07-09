/**
 * Central configuration for E2E tests.
 * Values come from environment variables (set in config/test.env or CI).
 */
import path from 'path'
import { fileURLToPath } from 'url'
import { readFileSync, existsSync } from 'fs'

function loadTestEnv(): Record<string, string> {
  const kitRoot = testKitRoot()
  const envPath = path.join(kitRoot, 'config', 'test.env')
  const vars: Record<string, string> = {}

  if (!existsSync(envPath)) {
    return vars
  }

  for (const line of readFileSync(envPath, 'utf-8').split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('#') || !trimmed.includes('=')) {
      continue
    }
    const [key, ...rest] = trimmed.split('=')
    vars[key.trim()] = rest.join('=').trim()
  }

  return vars
}

export function testKitRoot(): string {
  const currentDir = path.dirname(fileURLToPath(import.meta.url))
  return path.resolve(currentDir, '../..')
}

const fileEnv = loadTestEnv()

function env(key: string, fallback = ''): string {
  return process.env[key] ?? fileEnv[key] ?? fallback
}

export const testConfig = {
  projectRoot: env('PROJECT_ROOT'),
  baseURL: env('PLAYWRIGHT_BASE_URL', env('APP_URL', 'http://127.0.0.1:8000')),
  apiPrefix: env('API_PREFIX', '/api/v1'),
  testEmailDomain: env('TEST_EMAIL_DOMAIN', 'test.example.com'),
  mintTokenScript: env(
    'MINT_TOKEN_SCRIPT',
    'scripts/adapters/finolo/mint-token.php',
  ),
  pendingRegistrationModel: env(
    'PENDING_REGISTRATION_MODEL',
    'Modules\\User\\Models\\PendingRegistration',
  ),
}

export function apiPath(segment: string): string {
  const prefix = testConfig.apiPrefix.replace(/\/$/, '')
  const seg = segment.startsWith('/') ? segment : `/${segment}`
  return `${prefix}${seg}`
}

export function projectRoot(): string {
  if (!testConfig.projectRoot) {
    throw new Error(
      'PROJECT_ROOT is not set. Copy config/test.env.example to config/test.env',
    )
  }
  return testConfig.projectRoot
}

export function resolveMintTokenScript(): string {
  const script = testConfig.mintTokenScript
  if (path.isAbsolute(script)) {
    return script
  }
  return path.join(testKitRoot(), script)
}
