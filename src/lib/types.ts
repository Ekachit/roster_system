export type StaffRole = 'supervisor' | 'employee'

export interface Profile {
  id: string
  email: string
  full_name: string
  role: StaffRole
  is_active: boolean
}

export interface StaffRecord extends Profile {
  supervisor_notes: string | null
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
