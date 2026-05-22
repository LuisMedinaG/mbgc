import type { Page } from '@playwright/test'

/** Mock the login endpoint. No real credentials are ever transmitted. */
export async function mockLogin(
  page: Page,
  opts: { status?: number; error?: string } = {}
): Promise<void> {
  const status = opts.status ?? 200
  await page.route('**/api/v1/auth/login', (route) => {
    if (status === 200) {
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: { access_token: 'mock.jwt.access', refresh_token: 'mock.jwt.refresh' },
        }),
      })
    }
    return route.fulfill({
      status,
      contentType: 'application/json',
      body: JSON.stringify({ error: opts.error ?? 'unauthorized' }),
    })
  })
}
