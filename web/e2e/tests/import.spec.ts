import { test, expect } from '../fixtures/auth'
import { mockAll } from '../helpers/api-mocks'

async function bootWithOverrides(
  page: import('@playwright/test').Page,
  overrides: Parameters<typeof mockAll>[1] = {},
): Promise<void> {
  await mockAll(page, overrides)
  await page.addInitScript(() => {
    localStorage.setItem('mbgc_access', 'mock.jwt.access')
    localStorage.setItem('mbgc_refresh', 'mock.jwt.refresh')
  })
}

test.describe('Import — BGG sync', () => {
  test('preview button is disabled when no BGG username is set', async ({ page }) => {
    await bootWithOverrides(page, {
      profile: { bggUsername: '' },
      games: { empty: true },
      collections: { empty: true },
    })
    await page.goto('/#/import')
    await expect(page.getByRole('heading', { name: 'Import' })).toBeVisible({ timeout: 8000 })
    await expect(page.getByText(/set your bgg username/i)).toBeVisible()
    await expect(page.getByRole('button', { name: /preview/i })).toBeDisabled()
  })

  test('successful sync shows imported/skipped/failed counts', async ({ page }) => {
    await bootWithOverrides(page, {
      profile: { bggUsername: 'mytestuser', isAdmin: true },
      games: { empty: true },
      collections: { empty: true },
      bggPreview: { total: 10, owned: 2, new: 8 },
      bggSync: { body: { imported: 5, skipped: 2, failed: 1 } },
    })
    await page.goto('/#/import')
    await expect(page.getByRole('heading', { name: 'Import' })).toBeVisible({ timeout: 8000 })
    await page.getByRole('button', { name: /preview/i }).click()
    await page.getByRole('button', { name: /import \d+ game/i }).click()
    // The result panel shows all three counts as colored bullets
    await expect(page.getByText('Imported', { exact: true })).toBeVisible({ timeout: 8000 })
    await expect(page.getByText('Skipped', { exact: true })).toBeVisible()
    await expect(page.getByText('Failed', { exact: true })).toBeVisible()
    await expect(page.getByText('5', { exact: true }).first()).toBeVisible()
    await expect(page.getByText('2', { exact: true }).first()).toBeVisible()
    await expect(page.getByText('1', { exact: true }).first()).toBeVisible()
  })

  test('failed sync shows backend error message', async ({ page }) => {
    await bootWithOverrides(page, {
      profile: { bggUsername: 'mytestuser', isAdmin: true },
      games: { empty: true },
      collections: { empty: true },
      bggPreview: { total: 10, owned: 2, new: 8 },
      bggSync: { status: 500, error: 'BGG sync is not configured' },
    })
    await page.goto('/#/import')
    await expect(page.getByRole('heading', { name: 'Import' })).toBeVisible({ timeout: 8000 })
    await page.getByRole('button', { name: /preview/i }).click()
    await page.getByRole('button', { name: /import \d+ game/i }).click()
    await expect(page.getByText(/BGG sync is not configured/)).toBeVisible({ timeout: 8000 })
    await expect(page.getByText('[object Object]')).not.toBeVisible()
  })

  test('full refresh checkbox sends full_refresh=true', async ({ page }) => {
    const syncPromise = page.waitForRequest('**/api/v1/import/sync*')
    await bootWithOverrides(page, {
      profile: { bggUsername: 'mytestuser', isAdmin: true },
      games: { empty: true },
      collections: { empty: true },
      bggPreview: { total: 10, owned: 2, new: 8 },
    })
    await page.goto('/#/import')
    await expect(page.getByRole('heading', { name: 'Import' })).toBeVisible({ timeout: 8000 })
    await page.getByLabel(/full refresh/i).check()
    await page.getByRole('button', { name: /preview/i }).click()
    await page.getByRole('button', { name: /import \d+ game/i }).click()
    const req = await syncPromise
    expect(req.url()).toContain('full_refresh=true')
  })
})

test.describe('Import — CSV', () => {
  test('full flow: upload file → preview → import → done', async ({ page }) => {
    const importPromise = page.waitForRequest('**/api/v1/import/csv')
    await bootWithOverrides(page, {
      profile: { bggUsername: '' },
      games: { empty: true },
      collections: { empty: true },
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
    await bootWithOverrides(page, {
      profile: { bggUsername: '' },
      games: { empty: true },
      collections: { empty: true },
      csvImport: { previewStatus: 400 },
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
