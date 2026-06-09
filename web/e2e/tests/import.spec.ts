import { test, expect } from '../fixtures/auth'
import { mockBGGSync } from '../helpers/api-mocks'

test.describe('Import — BGG sync', () => {
  test('sync button is disabled when no BGG username is set', async ({ page }) => {
    // Profile with empty bgg_username
    await page.route('**/api/v1/ping', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { pong: true, username: 't' } }) }))
    await page.route('**/api/v1/profile', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { id: 'u1', username: 't', bgg_username: '', is_admin: false } }) }))
    await page.route('**/api/v1/games*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 20, total: 0 } }) }))
    await page.route('**/api/v1/collections*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 0, total: 0 } }) }))
    await page.route('**/api/v1/auth/refresh', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { access_token: 'mock.jwt.refreshed' } }) }))
    await page.addInitScript(() => {
      localStorage.setItem('mbgc_access', 'mock.jwt.access')
      localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
    })
    await page.goto('/#/import')
    await expect(page.getByRole('heading', { name: 'Import' })).toBeVisible({ timeout: 8000 })
    await expect(page.getByText(/set your bgg username/i)).toBeVisible()
    await expect(page.getByRole('button', { name: /sync from bgg/i })).toBeDisabled()
  })

  test('successful sync shows imported/skipped/failed counts', async ({ page }) => {
    await page.route('**/api/v1/ping', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { pong: true, username: 't' } }) }))
    await page.route('**/api/v1/profile', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { id: 'u1', username: 't', bgg_username: 'mytestuser', is_admin: true } }) }))
    await page.route('**/api/v1/games*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 20, total: 0 } }) }))
    await page.route('**/api/v1/collections*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 0, total: 0 } }) }))
    await page.route('**/api/v1/auth/refresh', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { access_token: 'mock.jwt.refreshed' } }) }))
    await mockBGGSync(page, { body: { imported: 5, skipped: 2, failed: 1 } })
    await page.addInitScript(() => {
      localStorage.setItem('mbgc_access', 'mock.jwt.access')
      localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
    })
    await page.goto('/#/import')
    await expect(page.getByRole('heading', { name: 'Import' })).toBeVisible({ timeout: 8000 })
    await page.getByRole('button', { name: /sync from bgg/i }).click()
    // The result panel must show all three counts — the bug was the type mismatch
    // causing `undefined` to render. We assert on the labels, which only show on success.
    await expect(page.getByText('Imported', { exact: true })).toBeVisible({ timeout: 8000 })
    await expect(page.getByText('Skipped', { exact: true })).toBeVisible()
    await expect(page.getByText('Failed', { exact: true })).toBeVisible()
    // And the values
    await expect(page.getByText('5', { exact: true }).first()).toBeVisible()
    await expect(page.getByText('2', { exact: true }).first()).toBeVisible()
    await expect(page.getByText('1', { exact: true }).first()).toBeVisible()
  })

  test('failed sync shows backend error message', async ({ page }) => {
    await page.route('**/api/v1/ping', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { pong: true, username: 't' } }) }))
    await page.route('**/api/v1/profile', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { id: 'u1', username: 't', bgg_username: 'mytestuser', is_admin: true } }) }))
    await page.route('**/api/v1/games*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 20, total: 0 } }) }))
    await page.route('**/api/v1/collections*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 0, total: 0 } }) }))
    await page.route('**/api/v1/auth/refresh', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { access_token: 'mock.jwt.refreshed' } }) }))
    await mockBGGSync(page, { status: 500, error: 'BGG sync is not configured' })
    await page.addInitScript(() => {
      localStorage.setItem('mbgc_access', 'mock.jwt.access')
      localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
    })
    await page.goto('/#/import')
    await expect(page.getByRole('heading', { name: 'Import' })).toBeVisible({ timeout: 8000 })
    await page.getByRole('button', { name: /sync from bgg/i }).click()
    await expect(page.getByText(/BGG sync is not configured/)).toBeVisible({ timeout: 8000 })
    await expect(page.getByText('[object Object]')).not.toBeVisible()
  })

  test('full refresh checkbox sends full_refresh=true', async ({ page }) => {
    await page.route('**/api/v1/ping', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { pong: true, username: 't' } }) }))
    await page.route('**/api/v1/profile', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { id: 'u1', username: 't', bgg_username: 'mytestuser', is_admin: true } }) }))
    await page.route('**/api/v1/games*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 20, total: 0 } }) }))
    await page.route('**/api/v1/collections*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 0, total: 0 } }) }))
    await page.route('**/api/v1/auth/refresh', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { access_token: 'mock.jwt.refreshed' } }) }))
    const syncPromise = page.waitForRequest('**/api/v1/import/sync*')
    await mockBGGSync(page)
    await page.addInitScript(() => {
      localStorage.setItem('mbgc_access', 'mock.jwt.access')
      localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
    })
    await page.goto('/#/import')
    await expect(page.getByRole('heading', { name: 'Import' })).toBeVisible({ timeout: 8000 })
    await page.getByLabel(/full refresh/i).check()
    await page.getByRole('button', { name: /sync from bgg/i }).click()
    const req = await syncPromise
    expect(req.url()).toContain('full_refresh=true')
  })
})

test.describe('Import — CSV', () => {
  test('full flow: upload file → preview → import → done', async ({ page }) => {
    await page.route('**/api/v1/ping', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { pong: true, username: 't' } }) }))
    await page.route('**/api/v1/profile', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { id: 'u1', username: 't', bgg_username: '', is_admin: false } }) }))
    await page.route('**/api/v1/games*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 20, total: 0 } }) }))
    await page.route('**/api/v1/collections*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 0, total: 0 } }) }))
    await page.route('**/api/v1/auth/refresh', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { access_token: 'mock.jwt.refreshed' } }) }))
    await page.route('**/api/v1/import/csv/preview', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          data: {
            rows: [
              { bgg_id: 174430, name: 'Gloomhaven', already_owned: false },
              { bgg_id: 13, name: 'Catan', already_owned: false },
            ],
            total_rows: 2,
            preview_limit: 100,
          },
          meta: { page: 1, limit: 2, total: 2 },
        }),
      }),
    )
    const importPromise = page.waitForRequest('**/api/v1/import/csv')
    await page.route('**/api/v1/import/csv', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ data: { imported: 2, failed: 0 } }),
      }),
    )

    await page.addInitScript(() => {
      localStorage.setItem('mbgc_access', 'mock.jwt.access')
      localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
    })
    await page.goto('/#/import/csv')
    await expect(page.getByRole('heading', { name: 'CSV Import' })).toBeVisible({ timeout: 8000 })

    // Step 1: upload
    await page.setInputFiles('input[type="file"]', {
      name: 'collection.csv',
      mimeType: 'text/csv',
      buffer: Buffer.from('objectid,objectname\n174430,Gloomhaven\n13,Catan\n'),
    })
    await page.getByRole('button', { name: 'Preview' }).click()

    // Step 2: preview shows both rows
    await expect(page.getByText('Gloomhaven').first()).toBeVisible({ timeout: 5000 })
    await expect(page.getByText('Catan').first()).toBeVisible()

    // Click import
    await page.getByRole('button', { name: /^Import 2 games$/ }).click()

    // Verify the import request body
    const req = await importPromise
    const body = JSON.parse(req.postData() ?? '{}')
    expect(body.bgg_ids).toEqual([174430, 13])

    // Step 3: done screen
    await expect(page.getByText('Import complete')).toBeVisible({ timeout: 5000 })
  })

  test('CSV with no objectid column shows error', async ({ page }) => {
    await page.route('**/api/v1/ping', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { pong: true, username: 't' } }) }))
    await page.route('**/api/v1/profile', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { id: 'u1', username: 't', bgg_username: '', is_admin: false } }) }))
    await page.route('**/api/v1/games*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 20, total: 0 } }) }))
    await page.route('**/api/v1/collections*', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: [], meta: { page: 1, limit: 0, total: 0 } }) }))
    await page.route('**/api/v1/auth/refresh', (route) =>
      route.fulfill({ status: 200, contentType: 'application/json',
        body: JSON.stringify({ data: { access_token: 'mock.jwt.refreshed' } }) }))
    await page.route('**/api/v1/import/csv/preview', (route) =>
      route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({ error: { code: 'BAD_REQUEST', message: "CSV must have an 'objectid' column" } }),
      }),
    )
    await page.addInitScript(() => {
      localStorage.setItem('mbgc_access', 'mock.jwt.access')
      localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
    })
    await page.goto('/#/import/csv')
    await expect(page.getByRole('heading', { name: 'CSV Import' })).toBeVisible({ timeout: 8000 })
    await page.setInputFiles('input[type="file"]', {
      name: 'bad.csv',
      mimeType: 'text/csv',
      buffer: Buffer.from('name,year\nGloomhaven,2017\n'),
    })
    await page.getByRole('button', { name: 'Preview' }).click()
    await expect(page.getByText(/objectid/i)).toBeVisible({ timeout: 5000 })
    await expect(page.getByText('[object Object]')).not.toBeVisible()
  })
})
