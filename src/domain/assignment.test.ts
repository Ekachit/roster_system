import { describe, expect, it } from 'vitest'
import { canOverrideConflicts, evaluateAssignmentCandidate, rosterWeekDays, type CandidateAssignmentInput } from './assignment'

const base: CandidateAssignmentInput = {
  employeeActive: true,
  locationEligible: true,
  activityEligible: true,
  localDate: '2026-07-27',
  shiftStart: '10:00',
  shiftEnd: '12:00',
  shiftId: 'shift-a',
  recurring: [{
    id: 'rule', staff_id: 'staff', weekday: 1, start_time: '09:00', end_time: '17:00',
    effective_start_date: '2026-01-01', effective_end_date: null, note: null,
  }],
  exceptions: [],
  activeAssignments: [],
}

describe('evaluateAssignmentCandidate', () => {
  it('builds a complete Monday-to-Sunday roster week', () => {
    expect(rosterWeekDays('2026-08-03')).toEqual([
      '2026-08-03', '2026-08-04', '2026-08-05', '2026-08-06',
      '2026-08-07', '2026-08-08', '2026-08-09',
    ])
  })

  it('accepts a fully available and eligible employee', () => {
    expect(evaluateAssignmentCandidate(base)).toMatchObject({
      eligible: true, fullyAvailable: true, assignableWithoutOverride: true, conflicts: [],
    })
  })

  it.each([
    [{ activeAssignments: [{ shiftId: 'shift-a', localDate: '2026-07-27', startTime: '10:00', endTime: '12:00' }] }, 'DUPLICATE_ASSIGNMENT'],
    [{ activeAssignments: [{ shiftId: 'shift-b', localDate: '2026-07-27', startTime: '11:00', endTime: '13:00' }] }, 'OVERLAPPING_ASSIGNMENT'],
    [{ employeeActive: false }, 'INACTIVE_EMPLOYEE'],
    [{ locationEligible: false }, 'LOCATION_NOT_ELIGIBLE'],
    [{ activityEligible: false }, 'ACTIVITY_NOT_ELIGIBLE'],
  ] as const)('returns structured %s conflict', (change, code) => {
    expect(evaluateAssignmentCandidate({ ...base, ...change }).conflicts.map((item) => item.code)).toContain(code)
  })

  it('distinguishes partial and date-specific unavailability', () => {
    const partial = evaluateAssignmentCandidate({
      ...base, recurring: [{ ...base.recurring[0], end_time: '11:00' }],
    })
    expect(partial.conflicts.map((item) => item.code)).toContain('PARTIALLY_AVAILABLE')
    const exception = evaluateAssignmentCandidate({
      ...base,
      exceptions: [{
        id: 'exception', staff_id: 'staff', local_date: '2026-07-27', kind: 'unavailable',
        start_time: null, end_time: null, is_full_day: true, note: null,
      }],
    })
    expect(exception.conflicts.map((item) => item.code)).toContain('DATE_SPECIFIC_UNAVAILABLE')
  })

  it('requires confirmation and reason and never overrides hard conflicts', () => {
    const warning = evaluateAssignmentCandidate({
      ...base, recurring: [{ ...base.recurring[0], end_time: '11:00' }],
    }).conflicts
    expect(canOverrideConflicts(warning, true, 'Approved for one-off coverage')).toBe(true)
    expect(canOverrideConflicts(warning, false, 'Approved')).toBe(false)
    expect(canOverrideConflicts(warning, true, ' ')).toBe(false)
    const duplicate = evaluateAssignmentCandidate({
      ...base,
      activeAssignments: [{ shiftId: 'shift-a', localDate: '2026-07-27', startTime: '10:00', endTime: '12:00' }],
    }).conflicts
    expect(canOverrideConflicts(duplicate, true, 'Try anyway')).toBe(false)
    expect(canOverrideConflicts(
      evaluateAssignmentCandidate({ ...base, locationEligible: false }).conflicts,
      true,
      'One off location',
    )).toBe(false)
  })
})
