import { expect, test, type APIRequestContext, type Dialog, type Page } from '@playwright/test'

const password = process.env.M7_E2E_PASSWORD
const supabaseUrl = process.env.VITE_SUPABASE_URL
const anonKey = process.env.VITE_SUPABASE_ANON_KEY
if (!password || !supabaseUrl || !anonKey) {
  throw new Error('Milestone 7 end-to-end environment is required')
}

const supervisorEmail = 'm7.e2e.supervisor@example.test'
const employeeEmail = 'm7.e2e.employee@example.test'
const replacementName = 'M7 E2E Replacement'
const shiftTitle = 'M7 complete workflow shift'

function addDays(date: string, days: number) {
  const value = new Date(`${date}T12:00:00Z`)
  value.setUTCDate(value.getUTCDate() + days)
  return value.toISOString().slice(0, 10)
}

function currentMelbourneMonday() {
  const today = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Australia/Melbourne',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date())
  const value = new Date(`${today}T12:00:00Z`)
  const weekday = value.getUTCDay() || 7
  return addDays(today, 1 - weekday)
}

async function signIn(page: Page, email: string, expectedHeading: string) {
  await page.goto('/sign-in')
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill(password as string)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page.getByRole('heading', { name: expectedHeading })).toBeVisible()
}

async function signOut(page: Page) {
  await page.getByRole('button', { name: 'Sign out' }).click()
  await expect(page.getByRole('heading', { name: 'Staff sign in' })).toBeVisible()
}

async function employeeToken(request: APIRequestContext) {
  const response = await request.post(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    headers: { apikey: anonKey as string, 'Content-Type': 'application/json' },
    data: { email: employeeEmail, password },
  })
  expect(response.ok()).toBe(true)
  return (await response.json() as { access_token: string }).access_token
}

test('complete MVP workflow, security boundary, reporting, CSV, responsive layout, and keyboard access', async ({ page, request }) => {
  test.setTimeout(120_000)
  const weekStart = currentMelbourneMonday()
  const shiftDate = addDays(weekStart, 27)

  await page.setViewportSize({ width: 390, height: 844 })
  await signIn(page, employeeEmail, 'Employee dashboard')
  await expect(page.getByRole('link', { name: 'Roster', exact: true })).toHaveCount(0)
  await expect(page.getByRole('link', { name: 'Reports', exact: true })).toHaveCount(0)

  await page.getByRole('link', { name: 'Availability', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'My availability' })).toBeVisible()

  const recurringForm = page.getByLabel('Weekday').locator('xpath=ancestor::form')
  await recurringForm.getByLabel('Weekday').selectOption('7')
  await recurringForm.getByLabel('Start time').fill('09:00')
  await recurringForm.getByLabel('End time').fill('17:00')
  await recurringForm.getByLabel('Effective from').fill(weekStart)
  await recurringForm.getByLabel('Note (optional)').fill('M7 synthetic recurring availability')
  await recurringForm.getByRole('button', { name: 'Add recurring rule' }).click()
  await expect(page.getByText('Recurring availability saved.')).toBeVisible()
  await expect(page.getByText(/Sunday.*09:00.*17:00/)).toBeVisible()

  const exceptionForm = page.getByLabel('Status').locator('xpath=ancestor::form')
  await exceptionForm.getByLabel('Date').fill(shiftDate)
  await exceptionForm.getByLabel('Status').selectOption('unavailable')
  await exceptionForm.getByLabel('Start time').fill('10:00')
  await exceptionForm.getByLabel('End time').fill('11:00')
  await exceptionForm.getByLabel('Note (optional)').fill('M7 synthetic date exception')
  await exceptionForm.getByRole('button', { name: 'Add date exception' }).click()
  await expect(page.getByText('Date exception saved.')).toBeVisible()
  await expect(page.getByText(new RegExp(`${shiftDate}.*10:00.*11:00`))).toBeVisible()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)

  await signOut(page)
  await page.setViewportSize({ width: 1440, height: 1000 })
  await signIn(page, supervisorEmail, 'Supervisor dashboard')
  await page.getByRole('link', { name: 'Roster', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Supervisor roster' })).toBeVisible()

  const shiftForm = page.getByLabel('Shift title').locator('xpath=ancestor::form')
  await shiftForm.getByLabel('Shift title').fill(shiftTitle)
  await shiftForm.getByLabel('Date').fill(shiftDate)
  await shiftForm.getByLabel('Start').fill('09:00')
  await shiftForm.getByLabel('End').fill('12:00')
  await shiftForm.getByLabel('Required staff').fill('1')
  await shiftForm.getByLabel('Location').selectOption({ label: 'Clayton' })
  await shiftForm.getByLabel('Activity').selectOption({ label: 'Training' })
  await shiftForm.getByLabel('Notes (optional)').fill('M7 employee-visible synthetic note')
  await shiftForm.getByRole('button', { name: 'Create shift' }).click()
  await expect(page.getByText('Draft shift created.')).toBeVisible()

  for (let week = 0; week < 3; week += 1) {
    await page.getByRole('button', { name: 'Next week' }).click()
  }
  const shiftCard = page.getByRole('article').filter({ hasText: shiftTitle })
  await expect(shiftCard).toContainText('Understaffed')
  await shiftCard.getByRole('button', { name: 'Manage' }).click()

  const employeeCandidate = page.getByRole('listitem').filter({ hasText: 'M7 E2E Employee' })
  await expect(employeeCandidate).toContainText('DATE_SPECIFIC_UNAVAILABLE')
  await expect(employeeCandidate).toContainText('date-specific exception makes the employee unavailable')

  const assignmentDialogs = ['accept', 'M7 availability override approved']
  const assignmentDialogHandler = async (dialog: Dialog) => {
    const response = assignmentDialogs.shift()
    await dialog.accept(response === 'accept' ? undefined : response)
  }
  page.on('dialog', assignmentDialogHandler)
  await employeeCandidate.getByRole('button', { name: 'Assign regular' }).click()
  await expect(page.getByText('M7 E2E Employee assigned.')).toBeVisible()
  page.off('dialog', assignmentDialogHandler)

  page.once('dialog', (dialog) => void dialog.accept())
  await shiftCard.getByRole('button', { name: 'Publish' }).click()
  await expect(page.getByText('Shift published.')).toBeVisible()
  await expect(shiftCard).toContainText('PUBLISHED')

  await signOut(page)
  await page.setViewportSize({ width: 390, height: 844 })
  await signIn(page, employeeEmail, 'Employee dashboard')
  await expect(page.getByText(shiftTitle, { exact: true })).toBeVisible()
  await page.getByRole('link', { name: 'View details' }).click()
  await expect(page.getByText('M7 employee-visible synthetic note')).toBeVisible()
  await page.getByRole('button', { name: 'Acknowledge shift' }).click()
  await expect(page.getByText(/^Acknowledged /)).toBeVisible()

  await page.getByRole('link', { name: 'Requests', exact: true }).click()
  const assignmentOption = page.getByLabel('Assigned shift').locator('option').filter({ hasText: shiftTitle })
  await page.getByLabel('Assigned shift').selectOption(await assignmentOption.getAttribute('value') as string)
  await page.getByLabel('Reason').fill('M7 synthetic release reason')
  await page.getByLabel('Explanatory note (optional)').fill('M7 synthetic release note')
  page.once('dialog', (dialog) => void dialog.accept())
  await page.getByRole('button', { name: 'Submit request' }).click()
  await expect(page.getByText('Request submitted. You remain assigned until a supervisor approves it.')).toBeVisible()
  await expect(page.getByRole('article').filter({ hasText: shiftTitle })).toContainText('Pending')

  await page.goto('/supervisor/roster')
  await expect(page.getByRole('heading', { name: 'Unauthorised' })).toBeVisible()

  const token = await employeeToken(request)
  const directHeaders = {
    apikey: anonKey as string,
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  }
  const directShiftMutation = await request.post(`${supabaseUrl}/rest/v1/shifts`, {
    headers: directHeaders,
    data: {
      shift_title: 'Unauthorized direct mutation',
      local_date: shiftDate,
      start_time: '13:00',
      end_time: '14:00',
    },
  })
  expect([401, 403]).toContain(directShiftMutation.status())
  const directReport = await request.post(`${supabaseUrl}/rest/v1/rpc/scheduled_hours_report`, {
    headers: directHeaders,
    data: { p_start_date: shiftDate, p_end_date: shiftDate },
  })
  expect(directReport.status()).toBe(403)
  expect(await directReport.text()).toContain('Supervisor access required')

  await signOut(page)
  await page.setViewportSize({ width: 1440, height: 1000 })
  await signIn(page, supervisorEmail, 'Supervisor dashboard')
  await page.getByRole('link', { name: 'Requests', exact: true }).click()
  const requestCard = page.getByRole('article').filter({ hasText: shiftTitle })
  await expect(requestCard).toContainText('M7 synthetic release reason')
  await requestCard.getByRole('button', { name: 'Open request and shift' }).click()
  const replacementOption = page.getByLabel('Replacement employee').locator('option').filter({ hasText: replacementName })
  await page.getByLabel('Replacement employee').selectOption(await replacementOption.getAttribute('value') as string)
  await expect(page.getByText('Eligible and fully available.')).toBeVisible()
  await page.getByLabel('Approval and replacement reason').fill('M7 replacement approved')
  page.once('dialog', (dialog) => void dialog.accept())
  await page.getByRole('button', { name: 'Confirm replacement' }).click()
  await expect(page.getByText('Request approved and replacement completed atomically.')).toBeVisible()

  await page.getByRole('link', { name: 'Audit', exact: true }).click()
  await page.getByLabel('Action').selectOption('RELEASE_REQUEST_APPROVED')
  const approvalAudit = page.getByRole('article').filter({ hasText: 'Release Request Approved' })
  await expect(approvalAudit).toContainText('M7 replacement approved')

  await page.getByRole('link', { name: 'Reports', exact: true }).click()
  await page.getByLabel('Start date').fill(shiftDate)
  await page.getByLabel('End date').fill(shiftDate)
  await page.getByRole('button', { name: 'Run report' }).click()
  const replacementReport = page.getByRole('row').filter({ hasText: replacementName }).first()
  await expect(replacementReport).toContainText('1')
  await expect(replacementReport).toContainText('3 hr')
  await expect(page.getByRole('row').filter({ hasText: 'M7 E2E Employee' })).toHaveCount(0)

  const downloadPromise = page.waitForEvent('download')
  await page.getByRole('button', { name: 'Export CSV' }).click()
  const download = await downloadPromise
  expect(download.suggestedFilename()).toBe(`scheduled-hours_${shiftDate}_to_${shiftDate}.csv`)
  const downloadPath = await download.path()
  expect(downloadPath).not.toBeNull()
  const csv = await (await import('node:fs/promises')).readFile(downloadPath as string, 'utf8')
  expect(csv).toContain(replacementName)
  expect(csv).toContain(',180,')
  expect(csv).not.toContain('M7 E2E Employee')

  await page.reload()
  await page.keyboard.press('Tab')
  await expect(page.getByRole('link', { name: 'Skip to content' })).toBeFocused()
})
