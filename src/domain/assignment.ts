import { resolveAvailability, type AvailabilityException, type RecurringAvailability } from './availability'

export const ASSIGNMENT_CONFLICT_CODES = [
  'DUPLICATE_ASSIGNMENT',
  'OVERLAPPING_ASSIGNMENT',
  'OUTSIDE_RECURRING_AVAILABILITY',
  'DATE_SPECIFIC_UNAVAILABLE',
  'PARTIALLY_AVAILABLE',
  'INACTIVE_EMPLOYEE',
  'LOCATION_NOT_ELIGIBLE',
  'ACTIVITY_NOT_ELIGIBLE',
] as const

export type AssignmentConflictCode = typeof ASSIGNMENT_CONFLICT_CODES[number]

export interface AssignmentConflict {
  code: AssignmentConflictCode
  message: string
  overridable: boolean
}

export interface CandidateAssignmentInput {
  employeeActive: boolean
  locationEligible: boolean
  activityEligible: boolean
  localDate: string
  shiftStart: string
  shiftEnd: string
  shiftId: string
  recurring: RecurringAvailability[]
  exceptions: AvailabilityException[]
  activeAssignments: ReadonlyArray<{
    shiftId: string
    localDate: string
    startTime: string
    endTime: string
  }>
}

export interface CandidateAssignmentResult {
  eligible: boolean
  fullyAvailable: boolean
  assignableWithoutOverride: boolean
  conflicts: AssignmentConflict[]
}

const conflict = (code: AssignmentConflictCode, message: string, overridable: boolean): AssignmentConflict => ({
  code, message, overridable,
})

export function evaluateAssignmentCandidate(input: CandidateAssignmentInput): CandidateAssignmentResult {
  const conflicts: AssignmentConflict[] = []
  if (!input.employeeActive) {
    conflicts.push(conflict('INACTIVE_EMPLOYEE', 'Employee is inactive.', false))
  }
  if (!input.locationEligible) {
    conflicts.push(conflict('LOCATION_NOT_ELIGIBLE', 'Employee is not eligible for this location.', false))
  }
  if (!input.activityEligible) {
    conflicts.push(conflict('ACTIVITY_NOT_ELIGIBLE', 'Employee is not eligible for this activity.', false))
  }
  if (input.activeAssignments.some((item) => item.shiftId === input.shiftId)) {
    conflicts.push(conflict('DUPLICATE_ASSIGNMENT', 'Employee is already actively assigned to this shift.', false))
  }
  if (input.activeAssignments.some((item) =>
    item.shiftId !== input.shiftId
    && item.localDate === input.localDate
    && item.startTime < input.shiftEnd
    && input.shiftStart < item.endTime
  )) {
    conflicts.push(conflict('OVERLAPPING_ASSIGNMENT', 'Employee has another active assignment at this time.', false))
  }

  const availability = resolveAvailability({
    employeeActive: input.employeeActive,
    localDate: input.localDate,
    shiftStart: input.shiftStart,
    shiftEnd: input.shiftEnd,
    recurring: input.recurring,
    exceptions: input.exceptions,
  })
  if (availability.status === 'date_specific_unavailable') {
    conflicts.push(conflict('DATE_SPECIFIC_UNAVAILABLE', 'A date-specific exception makes the employee unavailable.', true))
  } else if (availability.status === 'partially_available') {
    conflicts.push(conflict('PARTIALLY_AVAILABLE', 'Availability covers only part of the shift.', true))
  } else if (availability.status === 'no_recurring_availability') {
    conflicts.push(conflict('OUTSIDE_RECURRING_AVAILABILITY', 'Recurring availability does not cover this shift.', true))
  }

  return {
    eligible: input.employeeActive && input.locationEligible && input.activityEligible,
    fullyAvailable: availability.fullyAvailable,
    assignableWithoutOverride: conflicts.length === 0,
    conflicts,
  }
}

export function canOverrideConflicts(conflicts: AssignmentConflict[], confirmed: boolean, reason: string) {
  return conflicts.length > 0
    && conflicts.every((item) => item.overridable)
    && confirmed
    && reason.trim().length > 0
}

export function rosterWeekDays(mondayDate: string): string[] {
  const start = new Date(`${mondayDate}T12:00:00Z`)
  if (Number.isNaN(start.valueOf()) || (start.getUTCDay() || 7) !== 1) {
    throw new Error('Roster week must start on a valid Monday.')
  }
  return Array.from({ length: 7 }, (_, index) => {
    const day = new Date(start)
    day.setUTCDate(start.getUTCDate() + index)
    return day.toISOString().slice(0, 10)
  })
}
