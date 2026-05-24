import { test, expect } from '@playwright/test'
import { mockLogin } from '../helpers/mocks'

test.describe('Auth', () => {
  test('redirects unauthenticated users to /login', async ({ page }) => {
    await page.goto('/')
    await expect(page).toHaveURL(/#\/login/)
    await expect(page.getByRole('heading', { name: /board game collection/i })).toBeVisible()
  })

  test('login form submits and navigates to collection (mocked)', async ({ page }) => {
    await mockLogin(page)
    await page.goto('/#/login')
    await page.getByLabel('Username').fill('mock-user')
    await page.getByLabel('Password').fill('mock-pass')
    await page.getByRole('button', { name: /sign in/i }).click()
    await expect(page.getByRole('heading', { name: 'Board Game Collection' }))
      .toBeVisible({ timeout: 10000 })
  })

  test('login form shows error when backend rejects (mocked)', async ({ page }) => {
    await mockLogin(page, { status: 401, error: 'invalid username or password' })
    await page.goto('/#/login')
    await page.getByLabel('Username').fill('mock-user')
    await page.getByLabel('Password').fill('mock-pass')
    await page.getByRole('button', { name: /sign in/i }).click()
    await expect(page.getByText(/invalid username or password/i))
      .toBeVisible({ timeout: 5000 })
  })
})
