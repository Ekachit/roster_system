export const ROSTER_TIME_ZONE = 'Australia/Melbourne'
export const ISO_WEEKDAYS = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'] as const

export type AvailabilityKind = 'available' | 'unavailable'

export interface RecurringAvailability {
  id: string
  staff_id: string
  weekday: number
  start_time: string
  end_time: string
  effective_start_date: string
  effective_end_date: string | null
  note: string | null
}

export interface AvailabilityException {
  id: string
  staff_id: string
  local_date: string
  kind: AvailabilityKind
  start_time: string | null
  end_time: string | null
  is_full_day: boolean
  note: string | null
}

export type AvailabilityStatus =
  | 'fully_available'
  | 'partially_available'
  | 'no_recurring_availability'
  | 'date_specific_unavailable'
  | 'date_specific_available_override'
  | 'inactive_employee'
  | 'invalid_input'

export interface AvailabilityResolution {
  status: AvailabilityStatus
  fullyAvailable: boolean
  availableIntervals: Array<{ start: string; end: string }>
  reasons: string[]
  appliedRecurringIds: string[]
  appliedExceptionIds: string[]
  timezone: typeof ROSTER_TIME_ZONE
}

interface Interval { start: number; end: number }

function minutes(value: string | null): number | null {
  if (!value || !/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/.test(value)) return null
  const [hour, minute, second = 0] = value.split(':').map(Number)
  if (second !== 0) return null
  return hour * 60 + minute
}

function time(value: number) {
  return `${String(Math.floor(value / 60)).padStart(2, '0')}:${String(value % 60).padStart(2, '0')}`
}

function validDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false
  const parsed = new Date(`${value}T12:00:00Z`)
  return !Number.isNaN(parsed.valueOf()) && parsed.toISOString().slice(0, 10) === value
}

function isoWeekday(date: string) {
  const day = new Date(`${date}T12:00:00Z`).getUTCDay()
  return day === 0 ? 7 : day
}

function merge(intervals: Interval[]): Interval[] {
  const sorted = intervals.filter((item) => item.end > item.start).sort((a, b) => a.start - b.start)
  return sorted.reduce<Interval[]>((result, current) => {
    const previous = result.at(-1)
    if (previous && current.start <= previous.end) previous.end = Math.max(previous.end, current.end)
    else result.push({ ...current })
    return result
  }, [])
}

function subtract(intervals: Interval[], removed: Interval): Interval[] {
  return intervals.flatMap((item) => {
    if (removed.end <= item.start || removed.start >= item.end) return [item]
    const result: Interval[] = []
    if (removed.start > item.start) result.push({ start: item.start, end: removed.start })
    if (removed.end < item.end) result.push({ start: removed.end, end: item.end })
    return result
  })
}

function overlaps(a: Interval, b: Interval) {
  return a.start < b.end && b.start < a.end
}

export function resolveAvailability(input: {
  employeeActive: boolean
  localDate: string
  shiftStart: string
  shiftEnd: string
  recurring: RecurringAvailability[]
  exceptions: AvailabilityException[]
}): AvailabilityResolution {
  const base: Omit<AvailabilityResolution, 'status'> = {
    fullyAvailable: false,
    availableIntervals: [],
    reasons: [] as string[],
    appliedRecurringIds: [] as string[],
    appliedExceptionIds: [] as string[],
    timezone: ROSTER_TIME_ZONE,
  }
  if (!input.employeeActive) return { ...base, status: 'inactive_employee', reasons: ['Employee is inactive.'] }

  const shiftStart = minutes(input.shiftStart)
  const shiftEnd = minutes(input.shiftEnd)
  if (!validDate(input.localDate) || shiftStart === null || shiftEnd === null || shiftEnd <= shiftStart) {
    return { ...base, status: 'invalid_input', reasons: ['Use a valid Melbourne date and an end time later than the start time.'] }
  }
  const shift = { start: shiftStart, end: shiftEnd }
  const weekday = isoWeekday(input.localDate)
  const rules = input.recurring.filter((rule) =>
    rule.weekday === weekday
    && rule.effective_start_date <= input.localDate
    && (!rule.effective_end_date || rule.effective_end_date >= input.localDate)
  )
  const recurringIntervals: Interval[] = []
  for (const rule of rules) {
    const start = minutes(rule.start_time)
    const end = minutes(rule.end_time)
    if (start === null || end === null || end <= start) {
      return { ...base, status: 'invalid_input', reasons: [`Recurring rule ${rule.id} has an invalid time range.`] }
    }
    recurringIntervals.push({ start, end })
    base.appliedRecurringIds.push(rule.id)
  }

  let resolved = merge(recurringIntervals)
  const dayExceptions = input.exceptions.filter((item) => item.local_date === input.localDate)
  let unavailableApplied = false
  let availableApplied = false
  for (const exception of dayExceptions) {
    const start = exception.is_full_day ? 0 : minutes(exception.start_time)
    const end = exception.is_full_day ? 1440 : minutes(exception.end_time)
    if (start === null || end === null || end <= start || (exception.is_full_day && exception.kind !== 'unavailable')) {
      return { ...base, status: 'invalid_input', reasons: [`Date exception ${exception.id} is invalid.`] }
    }
    const interval = { start, end }
    if (exception.kind === 'available') {
      resolved = merge([...resolved, interval])
      availableApplied = availableApplied || overlaps(interval, shift)
    } else {
      resolved = subtract(resolved, interval)
      unavailableApplied = unavailableApplied || overlaps(interval, shift)
    }
    base.appliedExceptionIds.push(exception.id)
  }
  resolved = merge(resolved)
  const fullyAvailable = resolved.some((item) => item.start <= shift.start && item.end >= shift.end)
  const partiallyAvailable = resolved.some((item) => overlaps(item, shift))
  const availableIntervals = resolved.map((item) => ({ start: time(item.start), end: time(item.end) }))
  const common = { ...base, fullyAvailable, availableIntervals }

  if (fullyAvailable && availableApplied) {
    return { ...common, status: 'date_specific_available_override', reasons: ['A date-specific available exception covers this shift.'] }
  }
  if (fullyAvailable) {
    return { ...common, status: 'fully_available', reasons: ['Recurring availability covers the full shift.'] }
  }
  if (unavailableApplied) {
    return { ...common, status: 'date_specific_unavailable', reasons: ['A date-specific unavailable exception affects this shift.'] }
  }
  if (rules.length === 0 && !availableApplied) {
    return { ...common, status: 'no_recurring_availability', reasons: ['No recurring availability applies on this date.'] }
  }
  return {
    ...common,
    status: 'partially_available',
    reasons: [partiallyAvailable ? 'Availability covers only part of the shift.' : 'Availability does not cover this shift.'],
  }
}
