import { expect, test, type Page } from '@playwright/test'

const password = process.env.M4_BROWSER_PASSWORD
const apiUrl = process.env.VITE_SUPABASE_URL
const anonKey = process.env.VITE_SUPABASE_ANON_KEY
if (!password || !apiUrl || !anonKey) throw new Error('Milestone 4 browser environment is required')

async function signIn(page: Page) {
  await page.goto('/sign-in')
  await page.getByLabel('Email').fill('m4.browser.employee@example.test')
  await page.getByLabel('Password').fill(password as string)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page.getByRole('heading', { name: 'Employee dashboard' })).toBeVisible()
}

test('desktop employee sees exact titles and assignment kinds across dashboard, schedule, and details', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await signIn(page)

  const nextShift = page.getByRole('heading', { name: 'Next assigned shift' }).locator('..')
  await expect(nextShift).toContainText('Synthetic Saturday regular coverage')
  await expect(nextShift).toContainText('Regular')
  const thisWeek = page.getByRole('heading', { name: 'Published shifts this week' }).locator('..')
  await expect(thisWeek).toContainText('Synthetic Saturday regular coverage')
  await expect(thisWeek).toContainText('Synthetic Sunday shadow coverage')
  await expect(thisWeek).toContainText('Regular')
  await expect(thisWeek).toContainText('Shadowing')

  await page.getByRole('link', { name: 'My Schedule', exact: true }).click()
  const saturday = page.getByRole('article').filter({ hasText: 'Synthetic Saturday regular coverage' })
  const sunday = page.getByRole('article').filter({ hasText: 'Synthetic Sunday shadow coverage' })
  const cancelled = page.getByRole('article').filter({ hasText: 'Synthetic cancelled shadow history' })
  await expect(saturday).toContainText('Saturday 1 Aug')
  await expect(saturday).toContainText('Regular')
  await expect(sunday).toContainText('Sunday 2 Aug')
  await expect(sunday).toContainText('Shadowing')
  await expect(cancelled).toContainText('Cancelled')
  await expect(cancelled).toContainText('Shadowing')

  await saturday.getByRole('link', { name: 'View shift details' }).click()
  await expect(page.getByRole('heading', { name: 'Synthetic Saturday regular coverage' })).toBeVisible()
  await expect(page.getByText('Assigned (regular)')).toBeVisible()
  await expect(page.getByText('M4 Browser Colleague')).toBeVisible()

  await page.getByRole('link', { name: 'My Schedule', exact: true }).click()
  await cancelled.getByRole('link', { name: 'View shift details' }).click()
  await expect(page.getByRole('heading', { name: 'Synthetic cancelled shadow history' })).toBeVisible()
  await expect(page.getByText('Cancelled (shadowing)')).toBeVisible()
  await expect(page.getByText('This shift was cancelled.')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Acknowledge shift' })).toHaveCount(0)
})

test('authenticated PostgREST requests cannot retrieve internal shift or assignment columns', async ({ page }) => {
  await signIn(page)
  const results = await page.evaluate(async ({ apiBase, key }) => {
    const authEntry = Object.entries(localStorage).find(([name]) => name.endsWith('-auth-token'))
    if (!authEntry) throw new Error('Supabase auth storage was not found')
    const session = JSON.parse(authEntry[1]) as { access_token?: string }
    if (!session.access_token) throw new Error('Supabase access token was not found')
    const request = async (path: string) => {
      const response = await fetch(`${apiBase}/rest/v1/${path}`, {
        headers: { apikey: key, Authorization: `Bearer ${session.access_token}` },
      })
      return { status: response.status, body: await response.text() }
    }
    return Promise.all([
      request('shifts?select=id,created_by,updated_by,published_at,cancelled_at'),
      request('shift_assignments?select=id,assigned_by,override_reason,override_conflicts,removed_by,removal_reason'),
    ])
  }, { apiBase: apiUrl, key: anonKey })

  for (const result of results) {
    expect([401, 403]).toContain(result.status)
    expect(result.body).toContain('permission denied')
    expect(result.body).not.toContain('26000000-0000-0000-0000-000000000001')
  }
})

test('mobile employee can use weekend schedule, cancelled details, and acknowledgement without overflow', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await signIn(page)
  await expect(page.getByText('Synthetic Saturday regular coverage').first()).toBeVisible()
  await expect(page.getByText('Regular').first()).toBeVisible()

  await page.getByRole('link', { name: 'My Schedule', exact: true }).click()
  await expect(page.getByText('Saturday 1 Aug', { exact: true })).toBeVisible()
  await expect(page.getByText('Sunday 2 Aug', { exact: true })).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)

  const sunday = page.getByRole('article').filter({ hasText: 'Synthetic Sunday shadow coverage' })
  await sunday.getByRole('link', { name: 'View shift details' }).click()
  await expect(page.getByText('Assigned (shadowing)')).toBeVisible()
  await page.getByRole('button', { name: 'Acknowledge shift' }).click()
  await expect(page.getByText(/^Acknowledged /)).toBeVisible()
  await page.reload()
  await expect(page.getByText(/^Acknowledged /)).toBeVisible()

  await page.getByRole('link', { name: 'My Schedule', exact: true }).click()
  const cancelled = page.getByRole('article').filter({ hasText: 'Synthetic cancelled shadow history' })
  await cancelled.getByRole('link', { name: 'View shift details' }).click()
  await expect(page.getByText('Cancelled (shadowing)')).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)
})
