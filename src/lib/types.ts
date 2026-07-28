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

export interface EmployeeScheduleItem {
  assignment_id: string
  shift_id: string
  shift_title: string
  local_date: string
  start_time: string
  end_time: string
  location_name: string
  activity_name: string
  notes: string | null
  assignment_kind: AssignmentKind
  assignment_status: 'ASSIGNED' | 'CANCELLED' | 'REMOVED'
  shift_status: ShiftStatus
  acknowledged_at: string | null
  cancelled_at: string | null
  colleague_names: string[]
}

export type ReleaseRequestStatus = 'PENDING' | 'APPROVED' | 'REJECTED' | 'CANCELLED'

export interface ReleaseRequestAssignment {
  assignment_id: string
  shift_id: string
  shift_title: string
  local_date: string
  start_time: string
  end_time: string
  location_name: string
  activity_name: string
  assignment_kind: AssignmentKind
}

export interface EmployeeReleaseRequest {
  request_id: string
  assignment_id: string
  shift_id: string
  shift_title: string
  local_date: string
  start_time: string
  end_time: string
  location_name: string
  activity_name: string
  assignment_kind: AssignmentKind
  reason: string
  note: string | null
  status: ReleaseRequestStatus
  submitted_at: string
  resolved_at: string | null
  resolution_reason: string | null
}

export interface SupervisorReleaseRequest extends EmployeeReleaseRequest {
  staff_id: string
  employee_name: string
  assignment_active: boolean
  shift_status: ShiftStatus
  resolved_by_name: string | null
  replacement_assignment_id: string | null
}

export interface ReleaseCandidate {
  staff_id: string
  full_name: string
  conflicts: Array<{ code: string; message: string; overridable: boolean }>
  fully_available: boolean
  eligible: boolean
  assignable_without_override: boolean
}

export interface AuditHistoryRecord {
  audit_id: number
  actor_staff_id: string
  actor_name: string
  action: string
  entity_type: string
  entity_id: string | null
  shift_id: string | null
  assignment_id: string | null
  release_request_id: string | null
  subject_staff_id: string | null
  subject_name: string | null
  reason: string | null
  before_data: Record<string, unknown>
  after_data: Record<string, unknown>
  details: Record<string, unknown>
  created_at: string
}
