import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { EmptyState, ErrorState, LoadingState } from '../components/States'
import { supabase } from '../lib/supabase'
import type { ReferenceRecord, StaffRecord, StaffRole } from '../lib/types'

const initial = { email: '', full_name: '', role: 'employee' as StaffRole, supervisor_notes: '' }

export function StaffManagementPage() {
  const [rows, setRows] = useState<StaffRecord[]>([])
  const [form, setForm] = useState(initial)
  const [editing, setEditing] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [locations, setLocations] = useState<ReferenceRecord[]>([])
  const [activities, setActivities] = useState<ReferenceRecord[]>([])
  const [locationIds, setLocationIds] = useState<string[]>([])
  const [activityIds, setActivityIds] = useState<string[]>([])

  const load = useCallback(async () => {
    setLoading(true)
    const [{ data, error: queryError }, locationsResult, activitiesResult] = await Promise.all([
      supabase.from('supervisor_staff_directory').select('*').order('full_name'),
      supabase.from('locations').select('*').order('name'),
      supabase.from('activity_types').select('*').order('name'),
    ])
    setRows((data as StaffRecord[] | null) ?? [])
    setLocations((locationsResult.data as ReferenceRecord[] | null) ?? [])
    setActivities((activitiesResult.data as ReferenceRecord[] | null) ?? [])
    setError(queryError?.message ?? null)
    setLoading(false)
  }, [])

  useEffect(() => { void load() }, [load])

  async function save(event: FormEvent) {
    event.preventDefault()
    setError(null); setMessage(null)
    const { data: saved, error: saveError } = await supabase.rpc('save_staff_profile', {
      p_staff_id: editing,
      p_email: form.email.trim().toLowerCase(),
      p_full_name: form.full_name.trim(),
      p_role: form.role,
      p_supervisor_notes: form.supervisor_notes.trim() || null,
    })
    const result = { error: saveError, data: saved }
    if (result.error) setError(result.error.message)
    else {
      const staffId = result.data as string
      const eligibility = await supabase.rpc('set_staff_eligibility', { p_staff_id: staffId, p_location_ids: locationIds, p_activity_type_ids: activityIds })
      if (eligibility.error) { setError(eligibility.error.message); return }
      setMessage('Staff profile and eligibility saved.'); setForm(initial); setEditing(null); setLocationIds([]); setActivityIds([]); await load()
    }
  }

  async function beginEdit(row: StaffRecord) {
    setEditing(row.id)
    setForm({ email: row.email, full_name: row.full_name, role: row.role, supervisor_notes: row.supervisor_notes ?? '' })
    const [locationResult, activityResult] = await Promise.all([
      supabase.from('staff_locations').select('location_id').eq('staff_id', row.id),
      supabase.from('staff_activity_types').select('activity_type_id').eq('staff_id', row.id),
    ])
    setLocationIds((locationResult.data ?? []).map((item) => item.location_id))
    setActivityIds((activityResult.data ?? []).map((item) => item.activity_type_id))
  }

  function toggleId(id: string, values: string[], setValues: (next: string[]) => void) {
    setValues(values.includes(id) ? values.filter((value) => value !== id) : [...values, id])
  }

  async function toggle(row: StaffRecord) {
    setMessage(null)
    const { error: updateError } = await supabase.rpc('set_staff_active', { p_staff_id: row.id, p_is_active: !row.is_active })
    if (updateError) setError(updateError.message)
    else { setMessage(`${row.full_name} ${row.is_active ? 'deactivated' : 'activated'}.`); await load() }
  }

  return (
    <>
      <h1 className="text-3xl font-bold">Staff</h1>
      <p className="mt-2 text-slate-600">Approve staff before they sign in. Roles and private notes are supervisor-managed.</p>
      {message && <p className="mt-4 rounded-lg bg-green-50 p-3 text-green-900" role="status">{message}</p>}
      {error && <div className="mt-4"><ErrorState message={error} retry={() => void load()} /></div>}
      <form onSubmit={save} className="card mt-6 grid gap-4 sm:grid-cols-2">
        <label className="font-medium">Full name<input className="field" required value={form.full_name} onChange={(e) => setForm({ ...form, full_name: e.target.value })} /></label>
        <label className="font-medium">Email<input className="field" type="email" required value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} /></label>
        <label className="font-medium">Role<select className="field" value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value as StaffRole })}><option value="employee">Employee</option><option value="supervisor">Supervisor</option></select></label>
        <label className="font-medium">Supervisor-only notes<textarea className="field min-h-24" value={form.supervisor_notes} onChange={(e) => setForm({ ...form, supervisor_notes: e.target.value })} /></label>
        <fieldset><legend className="font-medium">Eligible locations</legend><div className="mt-2 grid gap-2">{locations.filter((item) => item.is_active).map((item) => <label key={item.id} className="flex items-center gap-2"><input type="checkbox" checked={locationIds.includes(item.id)} onChange={() => toggleId(item.id, locationIds, setLocationIds)} />{item.name}</label>)}</div></fieldset>
        <fieldset><legend className="font-medium">Eligible activity types</legend><div className="mt-2 grid gap-2">{activities.filter((item) => item.is_active).map((item) => <label key={item.id} className="flex items-center gap-2"><input type="checkbox" checked={activityIds.includes(item.id)} onChange={() => toggleId(item.id, activityIds, setActivityIds)} />{item.name}</label>)}</div></fieldset>
        <div className="flex gap-2 sm:col-span-2"><button className="button">{editing ? 'Update staff' : 'Add approved staff'}</button>{editing && <button type="button" className="button-secondary" onClick={() => { setEditing(null); setForm(initial); setLocationIds([]); setActivityIds([]) }}>Cancel</button>}</div>
      </form>
      <div className="mt-6">
        {loading ? <LoadingState /> : rows.length === 0 ? <EmptyState title="No approved staff" /> : <ul className="grid gap-3">{rows.map((row) => <li className="card flex flex-wrap items-start justify-between gap-3" key={row.id}><div><h2 className="font-semibold">{row.full_name}</h2><p className="text-sm text-slate-600">{row.email} · <span className="capitalize">{row.role}</span> · {row.is_active ? 'Active' : 'Inactive'}</p>{row.supervisor_notes && <p className="mt-2 text-sm"><span className="font-medium">Private note:</span> {row.supervisor_notes}</p>}</div><div className="flex gap-2"><button className="button-secondary" onClick={() => void beginEdit(row)}>Edit</button><button className="button-secondary" onClick={() => void toggle(row)}>{row.is_active ? 'Deactivate' : 'Activate'}</button></div></li>)}</ul>}
      </div>
    </>
  )
}
