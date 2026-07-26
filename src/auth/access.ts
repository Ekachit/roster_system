import type { Profile, StaffRole } from '../lib/types'

export type AccessResult = 'loading' | 'sign-in' | 'unapproved' | 'inactive' | 'unauthorised' | 'allowed'

export function resolveAccess(input: {
  loading: boolean
  authenticated: boolean
  profile: Profile | null
  requiredRole?: StaffRole
}): AccessResult {
  if (input.loading) return 'loading'
  if (!input.authenticated) return 'sign-in'
  if (!input.profile) return 'unapproved'
  if (!input.profile.is_active) return 'inactive'
  if (input.requiredRole && input.profile.role !== input.requiredRole) return 'unauthorised'
  return 'allowed'
}
