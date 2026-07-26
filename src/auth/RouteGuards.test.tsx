import { render, screen } from '@testing-library/react'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { describe, expect, it, vi } from 'vitest'
import type { Profile } from '../lib/types'
import { AuthContext, type AuthState } from './auth-context'
import { RequireAuth, RequireRole } from './RouteGuards'

const employee: Profile = {
  id: 'employee',
  email: 'employee@example.test',
  full_name: 'Alex Example',
  role: 'employee',
  is_active: true,
  email_matches: true,
}

function renderGuard(state: Partial<AuthState>, requiredRole?: 'employee' | 'supervisor') {
  const value: AuthState = {
    session: null,
    profile: null,
    loading: false,
    error: null,
    refreshProfile: vi.fn(),
    signOut: vi.fn(),
    ...state,
  }
  return render(
    <AuthContext.Provider value={value}>
      <MemoryRouter initialEntries={['/protected']}>
        <Routes>
          <Route path="/sign-in" element={<div>Sign-in page</div>} />
          <Route path="/unauthorised" element={<div>Unauthorised page</div>} />
          <Route element={<RequireAuth />}>
            {requiredRole ? (
              <Route element={<RequireRole role={requiredRole} />}>
                <Route path="/protected" element={<div>Protected content</div>} />
              </Route>
            ) : <Route path="/protected" element={<div>Protected content</div>} />}
          </Route>
        </Routes>
      </MemoryRouter>
    </AuthContext.Provider>,
  )
}

describe('actual route guards', () => {
  it('redirects an unauthenticated user and never renders protected content', () => {
    renderGuard({})
    expect(screen.getByText('Sign-in page')).toBeInTheDocument()
    expect(screen.queryByText('Protected content')).not.toBeInTheDocument()
  })

  it('redirects an employee from a supervisor route', () => {
    renderGuard({ session: {} as AuthState['session'], profile: employee }, 'supervisor')
    expect(screen.getByText('Unauthorised page')).toBeInTheDocument()
    expect(screen.queryByText('Protected content')).not.toBeInTheDocument()
  })

  it('renders a matching active role', () => {
    renderGuard({ session: {} as AuthState['session'], profile: employee }, 'employee')
    expect(screen.getByText('Protected content')).toBeInTheDocument()
  })

  it('shows the email-mismatch state instead of protected content', () => {
    renderGuard({ session: {} as AuthState['session'], profile: { ...employee, email_matches: false } })
    expect(screen.getByRole('heading', { name: 'Approved email mismatch' })).toBeInTheDocument()
    expect(screen.queryByText('Protected content')).not.toBeInTheDocument()
  })
})
