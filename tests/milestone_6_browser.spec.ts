import { expect, test, type Page } from '@playwright/test'
import { readFile } from 'node:fs/promises'

const password = process.env.M6_BROWSER_PASSWORD
const apiUrl = process.env.VITE_SUPABASE_URL
const anonKey = process.env.VITE_SUPABASE_ANON_KEY
if (!password || !apiUrl || !anonKey) throw new Error('Milestone 6 browser environment is required')

test.use({ timezoneId: 'America/Los_Angeles' })

const reportEmployeeId = '28000000-0000-0000-0000-000000000002'
const shadowEmployeeId = '28000000-0000-0000-0000-000000000003'
const formulaLocationId = '58000000-0000-0000-0000-000000000001'
const remoteLocationId = '58000000-0000-0000-0000-000000000002'
const formulaActivityId = '68000000-0000-0000-0000-000000000001'
const eventActivityId = '68000000-0000-0000-0000-000000000002'

interface Filters {
  employee?: string
  location?: string
  activity?: string
}

interface BrowserReportRow {
  shift_id: string
  staff_id: string
  employee_name: string
}

async function signIn(page: Page, email: string, expectedHeading: string) {
  await page.goto('/sign-in')
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill(password as string)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await expect(page.getByRole('heading', { name: expectedHeading })).toBeVisible()
}

async function runReport(page: Page, filters: Filters = {}) {
  await page.getByLabel('Employee').selectOption(filters.employee ?? '')
  await page.getByLabel('Location').selectOption(filters.location ?? '')
  await page.getByLabel('Activity type').selectOption(filters.activity ?? '')
  const response = page.waitForResponse((candidate) =>
    candidate.url().includes('/rest/v1/rpc/scheduled_hours_report')
    && candidate.request().method() === 'POST')
  await page.getByRole('button', { name: 'Run report' }).click()
  const result = await response
  expect(result.status()).toBe(200)
  return result.json() as Promise<BrowserReportRow[]>
}

function currentMelbourneWeek() {
  const today = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Australia/Melbourne',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date())
  const date = new Date(`${today}T12:00:00Z`)
  const weekday = date.getUTCDay() || 7
  date.setUTCDate(date.getUTCDate() + 1 - weekday)
  const startDate = date.toISOString().slice(0, 10)
  date.setUTCDate(date.getUTCDate() + 6)
  return { startDate, endDate: date.toISOString().slice(0, 10) }
}

function parseCsv(csv: string) {
  const rows: string[][] = []
  let row: string[] = []
  let cell = ''
  let quoted = false

  for (let index = 0; index < csv.length; index += 1) {
    const character = csv[index]
    if (quoted) {
      if (character === '"' && csv[index + 1] === '"') {
        cell += '"'
        index += 1
      } else if (character === '"') {
        quoted = false
      } else {
        cell += character
      }
    } else if (character === '"') {
      quoted = true
    } else if (character === ',') {
      row.push(cell)
      cell = ''
    } else if (character === '\r' && csv[index + 1] === '\n') {
      row.push(cell)
      rows.push(row)
      row = []
      cell = ''
      index += 1
    } else {
      cell += character
    }
  }

  if (cell || row.length) {
    row.push(cell)
    rows.push(row)
  }
  return rows
}

test('supervisor filters current scheduled hours and downloads the protected ten-column CSV', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await signIn(page, 'm6.browser.supervisor@example.test', 'Supervisor dashboard')
  await page.getByRole('link', { name: 'Reports', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Scheduled hours' })).toBeVisible()
  await expect(page.getByText(/does not represent attendance, actual worked hours or payroll/)).toBeVisible()

  const expectedWeek = currentMelbourneWeek()
  await expect(page.getByLabel('Start date')).toHaveValue(expectedWeek.startDate)
  await expect(page.getByLabel('End date')).toHaveValue(expectedWeek.endDate)

  await page.getByLabel('Start date').fill('2026-08-10')
  await page.getByLabel('End date').fill('2026-08-12')
  const allRows = await runReport(page)
  expect(allRows.map((row) => row.shift_id).sort()).toEqual([
    '38000000-0000-0000-0000-000000000001',
    '38000000-0000-0000-0000-000000000002',
    '38000000-0000-0000-0000-000000000003',
  ])
  expect(allRows.map((row) => row.shift_id)).not.toContain('38000000-0000-0000-0000-000000000004')
  expect(allRows.map((row) => row.shift_id)).not.toContain('38000000-0000-0000-0000-000000000005')
  expect(allRows.map((row) => row.shift_id)).not.toContain('38000000-0000-0000-0000-000000000006')

  const summary = page.getByRole('table').first()
  await expect(summary.locator('tbody tr')).toHaveCount(2)
  await expect(summary.locator('tbody tr').filter({ hasText: 'SUM(1,1)' })).toContainText('2')
  await expect(summary.locator('tbody tr').filter({ hasText: 'SUM(1,1)' })).toContainText('2 hr')
  await expect(summary.locator('tbody tr').filter({ hasText: 'M6 Browser Shadow Employee' })).toContainText('1 hr 15 min')
  await expect(page.locator('section.card tbody tr')).toHaveCount(3)
  await expect(page.getByText('Published', { exact: true })).toHaveCount(3)
  await expect(page.getByText('Assigned', { exact: true })).toHaveCount(3)

  await runReport(page, { employee: reportEmployeeId })
  await expect(page.getByRole('table').first().locator('tbody tr')).toHaveCount(1)
  await expect(page.locator('section.card tbody tr')).toHaveCount(2)

  await runReport(page, { location: formulaLocationId })
  await expect(page.getByRole('table').first().locator('tbody tr')).toHaveCount(2)
  await expect(page.locator('section.card tbody tr')).toHaveCount(2)

  await runReport(page, { activity: eventActivityId })
  await expect(page.getByRole('table').first().locator('tbody tr')).toHaveCount(2)
  await expect(page.locator('section.card tbody tr')).toHaveCount(2)

  await runReport(page, {
    employee: shadowEmployeeId,
    location: formulaLocationId,
    activity: eventActivityId,
  })
  await expect(page.getByRole('table').first().locator('tbody tr')).toHaveCount(1)
  await expect(page.locator('section.card tbody tr')).toHaveCount(1)
  await expect(page.getByRole('heading', { name: 'M6 Browser Shadow Employee' })).toBeVisible()

  await runReport(page, {
    employee: shadowEmployeeId,
    location: remoteLocationId,
    activity: formulaActivityId,
  })
  await expect(page.getByText('No scheduled hours match these filters')).toBeVisible()
  await expect(page.getByText(/Cancelled shifts and removed assignments are not included/)).toBeVisible()

  await runReport(page)
  const exportButton = page.getByRole('button', { name: 'Export CSV' })
  await expect(exportButton).toBeEnabled()
  await page.getByLabel('Activity type').selectOption(eventActivityId)
  await expect(exportButton).toBeDisabled()
  await expect(page.getByText(/Run the report to apply changed filters before exporting/)).toBeVisible()
  await runReport(page, { activity: eventActivityId })
  await page.getByLabel('Activity type').selectOption('')
  await expect(exportButton).toBeDisabled()
  await runReport(page)

  const downloadPromise = page.waitForEvent('download')
  await exportButton.click()
  const download = await downloadPromise
  expect(download.suggestedFilename()).toBe('scheduled-hours_2026-08-10_to_2026-08-12.csv')
  const downloadPath = await download.path()
  if (!downloadPath) throw new Error('Playwright did not provide a download path')
  const bytes = await readFile(downloadPath)
  expect([...bytes.subarray(0, 3)]).toEqual([0xEF, 0xBB, 0xBF])

  const content = bytes.toString('utf8')
  expect(content.endsWith('\r\n')).toBe(true)
  expect(content.replaceAll('\r\n', '')).not.toContain('\n')
  expect(content.replaceAll('\r\n', '')).not.toContain('\r')

  const records = parseCsv(content.slice(1))
  expect(records).toHaveLength(4)
  expect(records[0]).toEqual([
    'Employee name',
    'Employee email',
    'Date',
    'Start time',
    'End time',
    'Duration',
    'Location',
    'Activity type',
    'Shift status',
    'Assignment status',
  ])
  for (const record of records) expect(record).toHaveLength(10)

  const protectedRecord = records.find((record) => record[2] === '2026-08-10')
  expect(protectedRecord).toEqual([
    '\'=SUM(1,1), "Synthetic"\r\nEmployee',
    '\'+formula@example.test',
    '2026-08-10',
    '09:05',
    '10:35',
    '90',
    '\'＝Clayton, "Formula"',
    '\'@Training, "A"',
    'PUBLISHED',
    'ASSIGNED',
  ])

  for (const sensitiveValue of [
    'M6_SHIFT_NOTE_SENTINEL',
    'M6_PRIVATE_NOTE_SENTINEL',
    'M6_AVAILABILITY_SENTINEL',
    'M6_RELEASE_REASON_SENTINEL',
    'M6_RELEASE_NOTE_SENTINEL',
    'M6_AUDIT_REASON_SENTINEL',
    'M6_AUDIT_DATA_SENTINEL',
    'M6_REMOVAL_SENTINEL',
    '28000000-0000-0000-0000-000000000002',
    '38000000-0000-0000-0000-000000000001',
    '48000000-0000-0000-0000-000000000001',
  ]) {
    expect(content).not.toContain(sensitiveValue)
  }
})

test('supervisor report remains usable at a mobile viewport', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await signIn(page, 'm6.browser.supervisor@example.test', 'Supervisor dashboard')
  await page.getByRole('link', { name: 'Reports', exact: true }).click()
  await page.getByLabel('Start date').fill('2026-08-10')
  await page.getByLabel('End date').fill('2026-08-12')
  await runReport(page)

  await expect(page.getByRole('heading', { name: 'Scheduled hours' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Export CSV' })).toBeEnabled()
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth + 1)).toBe(true)
})

test('employee has no report UI and the report RPC fails closed without data', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await signIn(page, 'm6.browser.employee@example.test', 'Employee dashboard')
  await expect(page.getByRole('link', { name: 'Reports', exact: true })).toHaveCount(0)
  await page.goto('/supervisor/reports/hours')
  await expect(page.getByRole('heading', { name: 'Unauthorised' })).toBeVisible()

  const response = await page.evaluate(async ({ apiBase, key }) => {
    const authEntry = Object.entries(localStorage).find(([name]) => name.endsWith('-auth-token'))
    if (!authEntry) throw new Error('Supabase auth storage was not found')
    const session = JSON.parse(authEntry[1]) as { access_token?: string }
    if (!session.access_token) throw new Error('Supabase access token was not found')

    const result = await fetch(`${apiBase}/rest/v1/rpc/scheduled_hours_report`, {
      method: 'POST',
      headers: {
        apikey: key,
        Authorization: `Bearer ${session.access_token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        p_start_date: '2026-08-10',
        p_end_date: '2026-08-12',
        p_staff_id: null,
        p_location_id: null,
        p_activity_type_id: null,
      }),
    })
    return { status: result.status, body: await result.text() }
  }, { apiBase: apiUrl, key: anonKey })

  expect(response.status).toBe(403)
  expect(response.body).toContain('Supervisor access required')
  expect(response.body).not.toContain('SUM(1,1)')
  expect(response.body).not.toContain('M6 Browser Shadow Employee')
  expect(response.body).not.toContain('28000000-0000-0000-0000-000000000002')
})
