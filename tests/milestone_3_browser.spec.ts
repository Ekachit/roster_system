import { expect, test, type Page } from '@playwright/test'

const password = process.env.M3_BROWSER_PASSWORD
if (!password) throw new Error('M3_BROWSER_PASSWORD is required')

async function signIn(page: Page, email: string) {
  await page.goto('/sign-in')
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill(password as string)
  await page.getByRole('button', { name: 'Sign in' }).click()
}

test('synthetic supervisor completes the seven-day create, shadow, and publish workflow', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await signIn(page, 'browser.supervisor@example.test')
  await page.getByRole('link', { name: 'Roster', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Supervisor roster' })).toBeVisible()
  await expect(page.getByText('Monday–Sunday roster.')).toBeVisible()

  for (const day of ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']) {
    await expect(page.getByRole('heading', { name: new RegExp(`^${day}`) })).toBeVisible()
  }

  const createForm = page.getByRole('heading', { name: 'Create draft shift' }).locator('..')
  await createForm.getByLabel('Shift title').fill('Synthetic Sunday training')
  await createForm.getByLabel('Date').fill('2026-08-02')
  await createForm.getByLabel('Start').fill('10:00')
  await createForm.getByLabel('End').fill('12:00')
  await createForm.getByLabel('Required staff').fill('1')
  await createForm.getByLabel('Location').selectOption({ label: 'Clayton' })
  await createForm.getByLabel('Activity').selectOption({ label: 'Training' })
  await createForm.getByRole('button', { name: 'Create shift' }).click()
  await expect(page.getByText('Draft shift created.')).toBeVisible()
  const card = page.getByRole('article').filter({ hasText: 'Synthetic Sunday training' })
  await expect(card).toContainText('0/1 regular assigned')

  await card.getByRole('button', { name: 'Manage' }).click()
  const candidate = page.getByRole('listitem').filter({ hasText: 'Bailey Browser Employee' })
  await expect(candidate).toContainText('Eligible and fully available')
  await candidate.getByRole('button', { name: 'Assign shadowing' }).click()
  await expect(page.getByText('Bailey Browser Employee assigned.')).toBeVisible()
  await expect(card).toContainText('0/1 regular assigned')
  await expect(card).toContainText('1 shadowing')
  await expect(page.getByText('Bailey Browser Employee · Shadowing')).toBeVisible()
  page.once('dialog', (dialog) => dialog.accept())
  await card.getByRole('button', { name: 'Publish' }).click()
  await expect(page.getByText('Shift published.')).toBeVisible()
})

test('mobile employee cannot access supervisor roster or mutation controls', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await signIn(page, 'browser.employee@example.test')
  await expect(page.getByRole('heading', { name: 'Employee dashboard' })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Roster', exact: true })).toHaveCount(0)
  await page.goto('/supervisor/roster')
  await expect(page.getByRole('heading', { name: 'Unauthorised' })).toBeVisible()
  await expect(page.getByRole('button', { name: /Create shift|Publish|Assign/ })).toHaveCount(0)
})
