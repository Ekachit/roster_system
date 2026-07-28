import type { ScheduledHoursRow } from '../lib/types'

export const SCHEDULED_HOURS_CSV_HEADERS = [
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
] as const

export function formatDurationMinutes(totalMinutes: number) {
  const minutes = Math.max(0, Math.round(totalMinutes))
  const hours = Math.floor(minutes / 60)
  const remainder = minutes % 60

  if (hours === 0) return `${remainder} min`
  if (remainder === 0) return `${hours} hr`
  return `${hours} hr ${remainder} min`
}

const FORMULA_PREFIX = /^[=+\-@\t\r\n\uFF0B\uFF0D\uFF1D\uFF20]/

export function serializeCsvCell(value: string | number) {
  const text = typeof value === 'string' && FORMULA_PREFIX.test(value)
    ? `'${value}`
    : String(value)
  return /[",\t\r\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text
}

export function scheduledHoursCsv(rows: ScheduledHoursRow[]) {
  const body = rows.map((row) => [
    row.employee_name,
    row.employee_email,
    row.local_date,
    row.start_time.slice(0, 5),
    row.end_time.slice(0, 5),
    row.duration_minutes,
    row.location_name,
    row.activity_name,
    row.shift_status,
    row.assignment_status,
  ].map(serializeCsvCell).join(','))

  return `\uFEFF${[
    SCHEDULED_HOURS_CSV_HEADERS.map(serializeCsvCell).join(','),
    ...body,
  ].join('\r\n')}\r\n`
}

export function scheduledHoursFilename(startDate: string, endDate: string) {
  return `scheduled-hours_${startDate}_to_${endDate}.csv`
}
