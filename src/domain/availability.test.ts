import { describe, expect, it } from 'vitest'
import { ISO_WEEKDAYS, resolveAvailability, type AvailabilityException, type RecurringAvailability } from './availability'

const rule = (overrides: Partial<RecurringAvailability> = {}): RecurringAvailability => ({
  id: 'rule-1', staff_id: 'staff-1', weekday: 2, start_time: '09:00', end_time: '17:00',
  effective_start_date: '2026-01-01', effective_end_date: null, note: null, ...overrides,
})
const exception = (overrides: Partial<AvailabilityException> = {}): AvailabilityException => ({
  id: 'exception-1', staff_id: 'staff-1', local_date: '2026-07-28', kind: 'unavailable',
  start_time: '12:00', end_time: '14:00', is_full_day: false, note: null, ...overrides,
})
const resolve = (overrides: Partial<Parameters<typeof resolveAvailability>[0]> = {}) =>
  resolveAvailability({
    employeeActive: true, localDate: '2026-07-28', shiftStart: '10:00', shiftEnd: '12:00',
    recurring: [rule()], exceptions: [], ...overrides,
  })

describe('resolveAvailability', () => {
  it('exposes Saturday and Sunday ISO weekday labels', () => {
    expect(ISO_WEEKDAYS[6]).toBe('Saturday')
    expect(ISO_WEEKDAYS[7]).toBe('Sunday')
  })
  it('returns full availability', () => expect(resolve().status).toBe('fully_available'))
  it('returns partial availability', () => expect(resolve({ shiftStart: '16:00', shiftEnd: '18:00' }).status).toBe('partially_available'))
  it('applies an unavailable exception', () => expect(resolve({ shiftStart: '11:00', shiftEnd: '13:00', exceptions: [exception()] }).status).toBe('date_specific_unavailable'))
  it('applies an available override without a recurring rule', () => expect(resolve({
    recurring: [], exceptions: [exception({ kind: 'available', start_time: '10:00', end_time: '12:00' })],
  }).status).toBe('date_specific_available_override'))
  it('reports no recurring rule', () => expect(resolve({ recurring: [] }).status).toBe('no_recurring_availability'))
  it('merges overlapping rules deterministically', () => expect(resolve({
    shiftStart: '11:00', shiftEnd: '15:00',
    recurring: [rule({ end_time: '13:00' }), rule({ id: 'rule-2', start_time: '12:00', end_time: '17:00' })],
  }).fullyAvailable).toBe(true))
  it('rejects invalid shift and rule ranges', () => {
    expect(resolve({ shiftStart: '12:00', shiftEnd: '12:00' }).status).toBe('invalid_input')
    expect(resolve({ recurring: [rule({ end_time: '08:00' })] }).status).toBe('invalid_input')
  })
  it('reports inactive employees first', () => expect(resolve({ employeeActive: false }).status).toBe('inactive_employee'))
  it('resolves Saturday recurring availability', () => expect(resolve({
    localDate: '2026-08-01',
    recurring: [rule({ weekday: 6 })],
  }).status).toBe('fully_available'))
  it('resolves Sunday recurring availability', () => expect(resolve({
    localDate: '2026-08-02',
    recurring: [rule({ weekday: 7 })],
  }).status).toBe('fully_available'))
  it('reports no recurring availability on weekends', () => {
    expect(resolve({ localDate: '2026-08-01', recurring: [] }).status).toBe('no_recurring_availability')
    expect(resolve({ localDate: '2026-08-02', recurring: [] }).status).toBe('no_recurring_availability')
  })
  it('applies a weekend timed available override', () => expect(resolve({
    localDate: '2026-08-01',
    recurring: [],
    exceptions: [exception({
      local_date: '2026-08-01', kind: 'available', start_time: '10:00', end_time: '12:00',
    })],
  }).status).toBe('date_specific_available_override'))
  it('applies weekend timed and full-day unavailable exceptions', () => {
    expect(resolve({
      localDate: '2026-08-02', shiftStart: '11:00', shiftEnd: '13:00',
      recurring: [rule({ weekday: 7 })],
      exceptions: [exception({ local_date: '2026-08-02' })],
    }).status).toBe('date_specific_unavailable')
    expect(resolve({
      localDate: '2026-08-01',
      recurring: [rule({ weekday: 6 })],
      exceptions: [exception({
        local_date: '2026-08-01', start_time: null, end_time: null, is_full_day: true,
      })],
    }).status).toBe('date_specific_unavailable')
  })
  it('keeps Melbourne weekend dates stable at DST transitions', () => {
    expect(resolve({
      localDate: '2026-10-04',
      recurring: [rule({ weekday: 7, effective_start_date: '2026-10-04' })],
    }).status).toBe('fully_available')
    expect(resolve({
      localDate: '2026-04-05',
      recurring: [rule({ weekday: 7, effective_start_date: '2026-04-05' })],
    }).status).toBe('fully_available')
  })
})
