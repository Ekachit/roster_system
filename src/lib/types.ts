export type StaffRole = 'supervisor' | 'employee'

export interface Profile {
  id: string
  email: string
  full_name: string
  role: StaffRole
  is_active: boolean
  email_matches: boolean
}

export interface StaffRecord extends Profile {
  supervisor_notes: string | null
  is_linked: boolean
  location_ids?: string[]
  activity_type_ids?: string[]
}

export interface ReferenceRecord {
  id: string
  name: string
  is_active: boolean
  default_start_time: string | null
  default_end_time: string | null
}

export type { AvailabilityException, AvailabilityKind, RecurringAvailability } from '../domain/availability'

export type ShiftStatus = 'DRAFT' | 'PUBLISHED' | 'CANCELLED'
export type AssignmentKind = 'REGULAR' | 'SHADOWING'

export interface ShiftRecord {
  id: string
  shift_title: string
  local_date: string
  start_time: string
  end_time: string
  location_id: string
  activity_type_id: string
  required_staff_count: number
  notes: string | null
  status: ShiftStatus
  created_at: string
  updated_at: string
}

export interface ShiftAssignment {
  id: string
  shift_id: string
  staff_id: string
  assignment_kind: AssignmentKind
  assigned_at: string
  removed_at: string | null
}
