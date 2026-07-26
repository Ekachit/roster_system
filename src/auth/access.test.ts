import { describe, expect, it } from 'vitest'
import type { Profile } from '../lib/types'
import { resolveAccess } from './access'

const employee: Profile = { id: 'employee', email: 'employee@example.test', full_name: 'Alex Example', role: 'employee', is_active: true }
const supervisor: Profile = { ...employee, id: 'supervisor', role: 'supervisor' }

describe('resolveAccess', () => {
  it('requires unauthenticated users to sign in', () => {
    expect(resolveAccess({ loading: false, authenticated: false, profile: null })).toBe('sign-in')
  })
  it('rejects authenticated but unapproved users', () => {
    expect(resolveAccess({ loading: false, authenticated: true, profile: null })).toBe('unapproved')
  })
  it('rejects inactive users', () => {
    expect(resolveAccess({ loading: false, authenticated: true, profile: { ...employee, is_active: false } })).toBe('inactive')
  })
  it('does not allow an employee through a supervisor boundary', () => {
    expect(resolveAccess({ loading: false, authenticated: true, profile: employee, requiredRole: 'supervisor' })).toBe('unauthorised')
  })
  it('allows matching active roles', () => {
    expect(resolveAccess({ loading: false, authenticated: true, profile: supervisor, requiredRole: 'supervisor' })).toBe('allowed')
  })
})
