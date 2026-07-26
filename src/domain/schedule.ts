import { ROSTER_TIME_ZONE } from './availability'

export function todayMelbourne(now = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: ROSTER_TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(now)
}

export function currentMelbourneTime(now = new Date()) {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: ROSTER_TIME_ZONE,
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).format(now)
}

export function addScheduleDays(date: string, days: number) {
  const value = new Date(`${date}T12:00:00Z`)
  value.setUTCDate(value.getUTCDate() + days)
  return value.toISOString().slice(0, 10)
}

export function scheduleWeekStart(date: string) {
  const value = new Date(`${date}T12:00:00Z`)
  return addScheduleDays(date, 1 - (value.getUTCDay() || 7))
}

export function displayScheduleDate(date: string, includeYear = false) {
  return new Intl.DateTimeFormat('en-AU', {
    timeZone: ROSTER_TIME_ZONE,
    weekday: 'long',
    day: 'numeric',
    month: 'short',
    ...(includeYear ? { year: 'numeric' } : {}),
  }).format(new Date(`${date}T12:00:00Z`))
}

export function displayScheduleTime(time: string) {
  const [hour, minute] = time.split(':').map(Number)
  return new Intl.DateTimeFormat('en-AU', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
    timeZone: 'UTC',
  }).format(new Date(Date.UTC(2026, 0, 1, hour, minute)))
}
