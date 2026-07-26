import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { ErrorState, LoadingState, UnauthorisedState } from '../components/States'
import type { StaffRole } from '../lib/types'
import { useAuth } from './auth-context'
import { resolveAccess } from './access'

export function RequireAuth() {
  const { session, profile, loading, error, signOut } = useAuth()
  const location = useLocation()
  const access = resolveAccess({ loading, authenticated: Boolean(session), profile })
  if (access === 'loading') return <LoadingState label="Checking your access…" />
  if (access === 'sign-in') return <Navigate to="/sign-in" replace state={{ from: location }} />
  if (error) return <ErrorState message={error} />
  if (access === 'unapproved' || access === 'inactive' || access === 'email-mismatch') {
    return <main className="min-h-screen p-6"><UnauthorisedState reason={access} /><div className="mx-auto mt-4 max-w-xl"><button className="button-secondary" onClick={() => void signOut()}>Sign out</button></div></main>
  }
  return <Outlet />
}

export function RequireRole({ role }: { role: StaffRole }) {
  const { profile } = useAuth()
  if (resolveAccess({ loading: false, authenticated: true, profile, requiredRole: role }) !== 'allowed') return <Navigate to="/unauthorised" replace />
  return <Outlet />
}

export function RoleHome() {
  const { profile } = useAuth()
  return <Navigate to={profile?.role === 'supervisor' ? '/supervisor' : '/employee'} replace />
}
