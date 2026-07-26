import { useState, type FormEvent } from 'react'
import { useAuth } from '../auth/auth-context'
import { supabase } from '../lib/supabase'

export function SupervisorDashboard() {
  return <><h1 className="text-3xl font-bold">Supervisor dashboard</h1><p className="mt-2 text-slate-600">Manage the staff directory, availability, and weekly roster.</p><div className="mt-6 grid gap-4 sm:grid-cols-3">{['Roster', 'Staff', 'Availability', 'Locations', 'Activity types'].map((item) => <div className="card" key={item}><h2 className="font-semibold">{item}</h2><p className="mt-1 text-sm text-slate-600">Configuration is ready.</p></div>)}</div></>
}

export function EmployeeDashboard() {
  return <><h1 className="text-3xl font-bold">Employee dashboard</h1><p className="mt-2 text-slate-600">Welcome. Add your recurring weekly availability and any one-off exceptions from the Availability page.</p><div className="card mt-6"><h2 className="font-semibold">Availability is ready</h2><p className="mt-1 text-slate-600">Keep it current so future roster decisions can use the correct information.</p></div></>
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
