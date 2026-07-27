import { useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../auth/auth-context'
import { EmptyState, ErrorState, LoadingState } from '../components/States'
import { addScheduleDays, currentMelbourneTime, displayScheduleDate, displayScheduleTime, scheduleWeekStart, todayMelbourne } from '../domain/schedule'
import { supabase } from '../lib/supabase'
import { useEmployeeSchedule } from './useEmployeeSchedule'

export function SupervisorDashboard() {
  return <><h1 className="text-3xl font-bold">Supervisor dashboard</h1><p className="mt-2 text-slate-600">Manage the staff directory, availability, and weekly roster.</p><div className="mt-6 grid gap-4 sm:grid-cols-3">{['Roster', 'Staff', 'Availability', 'Locations', 'Activity types'].map((item) => <div className="card" key={item}><h2 className="font-semibold">{item}</h2><p className="mt-1 text-sm text-slate-600">Configuration is ready.</p></div>)}</div></>
}

export function EmployeeDashboard() {
  const { items, loading, error, load } = useEmployeeSchedule()
  const today = todayMelbourne()
  const nowTime = currentMelbourneTime()
  const weekStart = scheduleWeekStart(today)
  const weekEnd = addScheduleDays(weekStart, 6)
  const activeItems = items.filter((item) => item.shift_status === 'PUBLISHED')
  const upcoming = activeItems.filter((item) => item.local_date > today || (item.local_date === today && item.end_time > nowTime))
  const next = upcoming[0]
  const thisWeek = activeItems.filter((item) => item.local_date >= weekStart && item.local_date <= weekEnd)
  const outstanding = upcoming.filter((item) => !item.acknowledged_at).length

  return <div>
    <h1 className="text-3xl font-bold">Employee dashboard</h1>
    <p className="mt-2 text-slate-600">Your published roster at a glance. Times use Australia/Melbourne.</p>
    {loading ? <div className="mt-6"><LoadingState label="Loading your shifts…" /></div>
      : error ? <div className="mt-6"><ErrorState message={error} retry={() => void load()} /></div>
        : activeItems.length === 0 ? <div className="mt-6"><EmptyState title="No published shifts yet">When your supervisor publishes a shift assigned to you, it will appear here. Cancelled history remains available in My Schedule.</EmptyState><Link className="button-secondary mt-4" to="/employee/schedule">Open My Schedule</Link></div>
          : <>
            <div className="mt-6 grid gap-4 sm:grid-cols-3">
              <section className="card sm:col-span-2">
                <h2 className="font-semibold">Next assigned shift</h2>
                {next ? <div className="mt-3"><p className="text-lg font-semibold">{next.shift_title}</p><p className="mt-1 text-slate-600">{displayScheduleDate(next.local_date)} · {displayScheduleTime(next.start_time)}–{displayScheduleTime(next.end_time)}</p><p className="text-slate-600">{next.location_name} · {next.activity_name} · {next.assignment_kind === 'SHADOWING' ? 'Shadowing' : 'Regular'}</p><Link className="button-secondary mt-4" to={`/employee/shifts/${next.shift_id}`}>View details</Link></div>
                  : <p className="mt-3 text-slate-600">You have no upcoming published shifts.</p>}
              </section>
              <section className="card">
                <h2 className="font-semibold">Outstanding acknowledgements</h2>
                <p className="mt-3 text-4xl font-bold text-blue-800">{outstanding}</p>
                <Link className="mt-3 inline-block font-semibold text-blue-800 hover:underline" to="/employee/schedule">Open My Schedule</Link>
              </section>
            </div>
            <section className="card mt-4">
              <h2 className="font-semibold">Published shifts this week</h2>
              {thisWeek.length ? <ul className="mt-3 divide-y">{thisWeek.map((item) => <li className="flex flex-wrap items-center justify-between gap-2 py-3" key={item.assignment_id}><span><strong>{item.shift_title}</strong><span className="block text-sm text-slate-600">{displayScheduleDate(item.local_date)} · {displayScheduleTime(item.start_time)}–{displayScheduleTime(item.end_time)} · {item.location_name} · {item.assignment_kind === 'SHADOWING' ? 'Shadowing' : 'Regular'}</span></span><Link className="font-semibold text-blue-800 hover:underline" to={`/employee/shifts/${item.shift_id}`}>Details</Link></li>)}</ul>
                : <p className="mt-3 text-slate-600">No published shifts assigned to you this week.</p>}
            </section>
          </>}
  </div>
}

export function ProfilePage() {
  const { profile } = useAuth()
  const [password, setPassword] = useState('')
  const [confirmation, setConfirmation] = useState('')
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  async function changePassword(event: FormEvent) {
    event.preventDefault()
    setMessage(null)
    setError(null)
    if (password.length < 12) {
      setError('Use at least 12 characters.')
      return
    }
    if (password !== confirmation) {
      setError('The password confirmation does not match.')
      return
    }
    setSaving(true)
    const { error: updateError } = await supabase.auth.updateUser({ password })
    setSaving(false)
    if (updateError) {
      setError('Password change failed. Try again or contact the system owner.')
      return
    }
    setPassword('')
    setConfirmation('')
    setMessage('Password changed successfully.')
  }

  return <><h1 className="text-3xl font-bold">Profile</h1><dl className="card mt-6 grid gap-4 sm:grid-cols-2"><div><dt className="text-sm text-slate-500">Name</dt><dd className="font-medium">{profile?.full_name}</dd></div><div><dt className="text-sm text-slate-500">Email</dt><dd className="font-medium">{profile?.email}</dd></div><div><dt className="text-sm text-slate-500">Role</dt><dd className="font-medium capitalize">{profile?.role}</dd></div><div><dt className="text-sm text-slate-500">Timezone</dt><dd className="font-medium">Australia/Melbourne</dd></div></dl><form className="card mt-6 max-w-xl" onSubmit={changePassword}><h2 className="text-xl font-semibold">Change password</h2><p className="mt-1 text-sm text-slate-600">Change the temporary password supplied by the system owner after your first sign-in.</p>{error && <p className="mt-4 rounded-lg bg-red-50 p-3 text-red-900" role="alert">{error}</p>}{message && <p className="mt-4 rounded-lg bg-green-50 p-3 text-green-900" role="status">{message}</p>}<label className="mt-4 block font-medium">New password<input className="field" type="password" autoComplete="new-password" minLength={12} required value={password} onChange={(event) => setPassword(event.target.value)} /></label><label className="mt-4 block font-medium">Confirm new password<input className="field" type="password" autoComplete="new-password" minLength={12} required value={confirmation} onChange={(event) => setConfirmation(event.target.value)} /></label><button className="button mt-4" disabled={saving}>{saving ? 'Changing password…' : 'Change password'}</button></form></>
}

export function UnauthorisedPage() {
  return <div className="card" role="alert"><h1 className="text-2xl font-bold">Unauthorised</h1><p className="mt-2 text-slate-600">Your role does not permit access to that page.</p></div>
}
