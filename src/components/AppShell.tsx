import { NavLink, Outlet } from 'react-router-dom'
import { useAuth } from '../auth/AuthContext'

const linkClass = ({ isActive }: { isActive: boolean }) =>
  `rounded-lg px-3 py-2 text-sm font-medium ${isActive ? 'bg-blue-100 text-blue-900' : 'text-slate-700 hover:bg-slate-100'}`

export function AppShell() {
  const { profile, signOut } = useAuth()
  const supervisor = profile?.role === 'supervisor'
  return (
    <div className="min-h-screen">
      <a href="#main" className="sr-only focus:not-sr-only focus:absolute focus:z-50 focus:bg-white focus:p-3">Skip to content</a>
      <header className="border-b bg-white">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-3 px-4 py-3">
          <NavLink to="/" className="text-lg font-bold text-slate-950">AI Fitness Zone Roster</NavLink>
          <div className="text-sm text-slate-600">{profile?.full_name}</div>
          <nav aria-label="Primary" className="order-3 flex w-full gap-1 overflow-x-auto sm:order-none sm:w-auto">
            <NavLink className={linkClass} to={supervisor ? '/supervisor' : '/employee'}>Dashboard</NavLink>
            {supervisor && <>
              <NavLink className={linkClass} to="/supervisor/staff">Staff</NavLink>
              <NavLink className={linkClass} to="/supervisor/locations">Locations</NavLink>
              <NavLink className={linkClass} to="/supervisor/activity-types">Activities</NavLink>
            </>}
            <NavLink className={linkClass} to="/profile">Profile</NavLink>
          </nav>
          <button className="button-secondary min-h-9 px-3 py-1 text-sm" onClick={() => void signOut()}>Sign out</button>
        </div>
      </header>
      <main id="main" className="mx-auto max-w-6xl px-4 py-8"><Outlet /></main>
    </div>
  )
}
