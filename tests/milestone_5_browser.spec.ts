import { expect, test, type Page } from '@playwright/test'

const password = process.env.M5_BROWSER_PASSWORD
if (!password) throw new Error('Milestone 5 browser environment is required')

async function signIn(page: Page, email: string, expectedHeading: string) {
  const heading = page.getByRole('heading', { name: expectedHeading })
  for (let attempt = 0; attempt < 2; attempt += 1) {
    await page.goto('/sign-in')
    await page.getByLabel('Email').fill(email)
    await page.getByLabel('Password').fill(password as string)
    await page.getByRole('button', { name: 'Sign in' }).click()
    const signedIn = await heading.waitFor({ state: 'visible', timeout: 5_000 })
      .then(() => true)
      .catch(() => false)
    if (signedIn) return
  }
  await expect(heading).toBeVisible()
}

test('employee submits a request and supervisor replaces them through the controlled workflow', async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 })
  await signIn(page, 'm5.browser.employee@example.test', 'Employee dashboard')

  await page.getByRole('link', { name: 'Requests', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'My release requests' })).toBeVisible()
  await expect(page.getByText(/before a published shift or while it is in progress/i)).toBeVisible()
  const cancelledCard = page.getByRole('article').filter({ hasText: 'Synthetic cancelled release shift' })
  await expect(cancelledCard).toContainText('Cancelled')
  await expect(cancelledCard).toContainText('independently removed')
  await page.getByLabel('Assigned shift').selectOption('47000000-0000-0000-0000-000000000001')
  await page.getByLabel('Reason').fill('Synthetic personal commitment')
  await page.getByLabel('Explanatory note (optional)').fill('Synthetic browser workflow note')
  page.once('dialog', (dialog) => void dialog.accept())
  await page.getByRole('button', { name: 'Submit request' }).click()
  await expect(page.getByText('Request submitted. You remain assigned until a supervisor approves it.')).toBeVisible()
  const requestCard = page.getByRole('article').filter({ hasText: 'Synthetic release workflow shift' })
  await expect(requestCard).toContainText('Pending')
  await expect(requestCard).toContainText('Synthetic personal commitment')

  await page.goto('/employee/shifts/37000000-0000-0000-0000-000000000001')
  await expect(page.getByRole('heading', { name: 'Synthetic release workflow shift' })).toBeVisible()

  await page.getByRole('button', { name: 'Sign out' }).click()
  await signIn(page, 'm5.browser.supervisor@example.test', 'Supervisor dashboard')
  await page.getByRole('link', { name: 'Requests', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Release requests' })).toBeVisible()
  await expect(page.getByText('Synthetic personal commitment')).toBeVisible()
  await page.getByRole('button', { name: 'Open request and shift' }).click()
  await expect(page.getByRole('heading', { name: 'M5 Browser Employee', exact: true })).toBeVisible()
  await page.getByLabel('Replacement employee').selectOption('27000000-0000-0000-0000-000000000003')
  await expect(page.getByText('Eligible and fully available.')).toBeVisible()
  await page.getByLabel('Approval and replacement reason').fill('Synthetic replacement approved')
  page.once('dialog', (dialog) => void dialog.accept())
  await page.getByRole('button', { name: 'Confirm replacement' }).click()
  await expect(page.getByText('Request approved and replacement completed atomically.')).toBeVisible()

  await page.getByLabel('Status').selectOption('APPROVED')
  await expect(page.getByText('Approved').first()).toBeVisible()
  await page.getByRole('link', { name: 'Audit', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Audit history' })).toBeVisible()
  await page.getByLabel('Action').selectOption('RELEASE_REQUEST_APPROVED')
  const auditEvent = page.getByRole('article').filter({ hasText: 'Release Request Approved' })
  await expect(auditEvent).toContainText('Synthetic replacement approved')
})

test('employee request page remains usable without horizontal overflow on mobile', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await signIn(page, 'm5.browser.employee@example.test', 'Employee dashboard')
  await page.getByRole('link', { name: 'Requests', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'My release requests' })).toBeVisible()
  await expect(page.getByText(/before a published shift or while it is in progress/i)).toBeVisible()
  await expect(
    page.getByRole('article').filter({ hasText: 'Synthetic cancelled release shift' }),
  ).toContainText('Cancelled')
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)
})
