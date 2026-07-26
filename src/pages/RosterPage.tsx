import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { ROSTER_TIME_ZONE } from '../domain/availability'
import { rosterWeekDays } from '../domain/assignment'
import { supabase } from '../lib/supabase'
import type { AssignmentKind, ReferenceRecord, ShiftAssignment, ShiftRecord, StaffRecord } from '../lib/types'
import { EmptyState, ErrorState, LoadingState } from '../components/States'

interface Candidate {
  staff_id: string
  full_name: string
  conflicts: Array<{ code: string; message: string; overridable: boolean }>
  fully_available: boolean
  eligible: boolean
  assignable_without_override: boolean
}
interface Staffing {
  required_staff_count: number
  regular_assigned_count: number
  shadowing_count: number
  understaffed: boolean
}

const todayMelbourne = () => new Intl.DateTimeFormat('en-CA', {
  timeZone: ROSTER_TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date())

function addDays(date: string, days: number) {
  const value = new Date(`${date}T12:00:00Z`)
  value.setUTCDate(value.getUTCDate() + days)
  return value.toISOString().slice(0, 10)
}

function monday(date: string) {
  const value = new Date(`${date}T12:00:00Z`)
  const weekday = value.getUTCDay() || 7
  return addDays(date, 1 - weekday)
}

function displayDate(date: string) {
  return new Intl.DateTimeFormat('en-AU', {
    timeZone: ROSTER_TIME_ZONE, weekday: 'short', day: 'numeric', month: 'short',
  }).format(new Date(`${date}T12:00:00Z`))
}

const blankForm = () => ({
  shift_title: '', local_date: todayMelbourne(), start_time: '09:00', end_time: '17:00',
  location_id: '', activity_type_id: '', required_staff_count: 1, notes: '',
})

export function RosterPage() {
  const [week, setWeek] = useState(() => monday(todayMelbourne()))
  const [shifts, setShifts] = useState<ShiftRecord[]>([])
  const [assignments, setAssignments] = useState<ShiftAssignment[]>([])
  const [staff, setStaff] = useState<StaffRecord[]>([])
  const [locations, setLocations] = useState<ReferenceRecord[]>([])
  const [activities, setActivities] = useState<ReferenceRecord[]>([])
  const [locationFilter, setLocationFilter] = useState('')
  const [activityFilter, setActivityFilter] = useState('')
  const [form, setForm] = useState(blankForm)
  const [editing, setEditing] = useState<string | null>(null)
  const [selected, setSelected] = useState<string | null>(null)
  const [candidates, setCandidates] = useState<Candidate[]>([])
  const [staffing, setStaffing] = useState<Record<string, Staffing>>({})
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const days = useMemo(() => rosterWeekDays(week), [week])

  const load = useCallback(async () => {
    setLoading(true)
    const end = addDays(week, 6)
    const [shiftRows, assignmentRows, people, placeRows, activityRows] = await Promise.all([
      supabase.from('shifts').select('*').gte('local_date', week).lte('local_date', end).order('local_date').order('start_time'),
      supabase.from('shift_assignments').select('*').is('removed_at', null),
      supabase.from('supervisor_staff_directory').select('*').order('full_name'),
      supabase.from('locations').select('*').order('name'),
      supabase.from('activity_types').select('*').order('name'),
    ])
    setShifts((shiftRows.data as ShiftRecord[] | null) ?? [])
    const loadedShifts = (shiftRows.data as ShiftRecord[] | null) ?? []
    const staffingRows = await Promise.all(loadedShifts.map(async (shift) => {
      const result = await supabase.rpc('shift_staffing', { p_shift_id: shift.id })
      return [shift.id, (result.data as Staffing[] | null)?.[0]] as const
    }))
    setStaffing(Object.fromEntries(staffingRows.filter((entry): entry is readonly [string, Staffing] => Boolean(entry[1]))))
    setAssignments((assignmentRows.data as ShiftAssignment[] | null) ?? [])
    setStaff((people.data as StaffRecord[] | null) ?? [])
    setLocations((placeRows.data as ReferenceRecord[] | null) ?? [])
    setActivities((activityRows.data as ReferenceRecord[] | null) ?? [])
    setError((shiftRows.error ?? assignmentRows.error ?? people.error ?? placeRows.error ?? activityRows.error)?.message ?? null)
    setLoading(false)
  }, [week])

  useEffect(() => { void load() }, [load])
  useEffect(() => {
    if (!selected) return setCandidates([])
    void supabase.rpc('shift_candidates', { p_shift_id: selected }).then(({ data, error: candidateError }) => {
      setCandidates((data as Candidate[] | null) ?? [])
      if (candidateError) setError(candidateError.message)
    })
  }, [selected, assignments])

  const activeAssignments = (shiftId: string) => assignments.filter((item) => item.shift_id === shiftId)
  const name = (id: string) => staff.find((item) => item.id === id)?.full_name ?? 'Unknown'
  const locationName = (id: string) => locations.find((item) => item.id === id)?.name ?? 'Unknown'
  const activityName = (id: string) => activities.find((item) => item.id === id)?.name ?? 'Unknown'

  async function save(event: FormEvent) {
    event.preventDefault(); setError(null); setMessage(null); setSaving(true)
    const { error: saveError } = await supabase.rpc('save_shift', {
      p_shift_id: editing, p_local_date: form.local_date, p_start_time: form.start_time,
      p_shift_title: form.shift_title,
      p_end_time: form.end_time, p_location_id: form.location_id,
      p_activity_type_id: form.activity_type_id, p_required_staff_count: form.required_staff_count,
      p_notes: form.notes,
    })
    setSaving(false)
    if (saveError) return setError(saveError.message)
    setMessage(editing ? 'Draft shift updated.' : 'Draft shift created.')
    setEditing(null); setForm(blankForm()); await load()
  }

  function edit(shift: ShiftRecord) {
    setEditing(shift.id)
    setForm({
      shift_title: shift.shift_title, local_date: shift.local_date, start_time: shift.start_time.slice(0, 5),
      end_time: shift.end_time.slice(0, 5), location_id: shift.location_id,
      activity_type_id: shift.activity_type_id, required_staff_count: shift.required_staff_count,
      notes: shift.notes ?? '',
    })
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }

  async function status(shift: ShiftRecord, next: 'DRAFT' | 'PUBLISHED' | 'CANCELLED') {
    const needsReason = next !== 'PUBLISHED'
    const reason = needsReason ? window.prompt(`${next === 'DRAFT' ? 'Unpublish' : 'Cancel'} reason:`) : null
    if (needsReason && !reason?.trim()) return
    if (!window.confirm(`${next === 'PUBLISHED' ? 'Publish' : next === 'DRAFT' ? 'Unpublish' : 'Cancel'} this shift?`)) return
    const result = await supabase.rpc('set_shift_status', { p_shift_id: shift.id, p_status: next, p_reason: reason })
    if (result.error) return setError(result.error.message)
    setMessage(`Shift ${next.toLowerCase()}.`); await load()
  }

  async function copy(shift: ShiftRecord) {
    const date = window.prompt('Copy to date (YYYY-MM-DD):', shift.local_date)
    if (!date) return
    const result = await supabase.rpc('copy_shift', { p_shift_id: shift.id, p_local_date: date })
    if (result.error) return setError(result.error.message)
    setMessage('Draft copy created without assignments.'); await load()
  }

  async function assign(candidate: Candidate, assignmentKind: AssignmentKind) {
    let confirmed = false
    let reason: string | null = null
    if (candidate.conflicts.length) {
      if (candidate.conflicts.some((item) => !item.overridable)) return
      confirmed = window.confirm(`Override these warnings?\n${candidate.conflicts.map((item) => item.message).join('\n')}`)
      if (!confirmed) return
      reason = window.prompt('Written override reason:')
      if (!reason?.trim()) return
    }
    const result = await supabase.rpc('assign_employee', {
      p_shift_id: selected, p_staff_id: candidate.staff_id,
      p_assignment_kind: assignmentKind,
      p_override_confirmed: confirmed, p_override_reason: reason,
    })
    if (result.error) return setError(result.error.message)
    setMessage(`${candidate.full_name} assigned.`); await load()
  }

  async function remove(assignment: ShiftAssignment) {
    const reason = window.prompt('Removal reason:')
    if (!reason?.trim()) return
    const result = await supabase.rpc('remove_employee', { p_assignment_id: assignment.id, p_reason: reason })
    if (result.error) return setError(result.error.message)
    setMessage(`${name(assignment.staff_id)} removed; history preserved.`); await load()
  }

  async function replace(assignment: ShiftAssignment) {
    const replacement = window.prompt(`Replacement employee ID:\n${candidates.map((item) => `${item.full_name}: ${item.staff_id}`).join('\n')}`)
    if (!replacement) return
    const candidate = candidates.find((item) => item.staff_id === replacement)
    if (!candidate || candidate.conflicts.some((item) => !item.overridable)) return setError('Select an assignable replacement employee ID.')
    let overrideReason: string | null = null
    let confirmed = false
    if (candidate.conflicts.length) {
      confirmed = window.confirm(candidate.conflicts.map((item) => item.message).join('\n'))
      if (!confirmed) return
      overrideReason = window.prompt('Written override reason:')
      if (!overrideReason?.trim()) return
    }
    const replacementReason = window.prompt('Replacement reason:')
    if (!replacementReason?.trim()) return
    const result = await supabase.rpc('replace_employee', {
      p_assignment_id: assignment.id, p_replacement_staff_id: replacement,
      p_assignment_kind: assignment.assignment_kind,
      p_override_confirmed: confirmed, p_override_reason: overrideReason,
      p_replacement_reason: replacementReason,
    })
    if (result.error) return setError(result.error.message)
    setMessage('Employee replaced in one transaction; prior assignment retained in history.'); await load()
  }

  const filtered = shifts.filter((item) =>
    (!locationFilter || item.location_id === locationFilter)
    && (!activityFilter || item.activity_type_id === activityFilter)
  )
  const selectedShift = shifts.find((item) => item.id === selected)

  return <div>
    <h1 className="text-3xl font-bold">Supervisor roster</h1>
    <p className="mt-2 text-slate-600">Monday–Sunday roster. All dates and times use {ROSTER_TIME_ZONE}.</p>
    {message && <p className="mt-4 rounded-lg bg-green-50 p-3 text-green-900" role="status">{message}</p>}
    {error && <div className="mt-4"><ErrorState message={error} retry={() => void load()} /></div>}

    <form className="card mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4" onSubmit={save}>
      <h2 className="text-xl font-semibold sm:col-span-2 lg:col-span-4">{editing ? 'Edit draft shift' : 'Create draft shift'}</h2>
      <label className="font-medium sm:col-span-2">Shift title<input className="field" required value={form.shift_title} onChange={(e) => setForm({ ...form, shift_title: e.target.value })} /></label>
      <label className="font-medium">Date<input className="field" type="date" required value={form.local_date} onChange={(e) => setForm({ ...form, local_date: e.target.value })} /></label>
      <label className="font-medium">Start<input className="field" type="time" required value={form.start_time} onChange={(e) => setForm({ ...form, start_time: e.target.value })} /></label>
      <label className="font-medium">End<input className="field" type="time" required value={form.end_time} onChange={(e) => setForm({ ...form, end_time: e.target.value })} /></label>
      <label className="font-medium">Required staff<input className="field" type="number" min="1" required value={form.required_staff_count} onChange={(e) => setForm({ ...form, required_staff_count: Number(e.target.value) })} /></label>
      <label className="font-medium">Location<select className="field" required value={form.location_id} onChange={(e) => setForm({ ...form, location_id: e.target.value })}><option value="">Select</option>{locations.filter((item) => item.is_active).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      <label className="font-medium">Activity<select className="field" required value={form.activity_type_id} onChange={(e) => setForm({ ...form, activity_type_id: e.target.value })}><option value="">Select</option>{activities.filter((item) => item.is_active).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      <label className="font-medium sm:col-span-2">Notes (optional)<input className="field" value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} /></label>
      <div className="flex gap-2 sm:col-span-2 lg:col-span-4"><button className="button" disabled={saving}>{saving ? 'Saving…' : editing ? 'Update draft' : 'Create shift'}</button>{editing && <button className="button-secondary" type="button" onClick={() => { setEditing(null); setForm(blankForm()) }}>Cancel edit</button>}</div>
    </form>

    <div className="card mt-6 flex flex-wrap items-end gap-3">
      <button className="button-secondary" onClick={() => setWeek(addDays(week, -7))}>Previous week</button>
      <button className="button-secondary" onClick={() => setWeek(monday(todayMelbourne()))}>Current week</button>
      <button className="button-secondary" onClick={() => setWeek(addDays(week, 7))}>Next week</button>
      <label className="min-w-44 font-medium">Location<select className="field" value={locationFilter} onChange={(e) => setLocationFilter(e.target.value)}><option value="">All locations</option>{locations.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
      <label className="min-w-44 font-medium">Activity<select className="field" value={activityFilter} onChange={(e) => setActivityFilter(e.target.value)}><option value="">All activities</option>{activities.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
    </div>

    {loading ? <div className="mt-6"><LoadingState /></div> : <div className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-7">
      {days.map((day) => <section key={day} aria-labelledby={`day-${day}`}>
        <h2 id={`day-${day}`} className="mb-3 text-lg font-semibold">{displayDate(day)}</h2>
        <div className="grid gap-3">{filtered.filter((item) => item.local_date === day).map((shift) => {
          const counts = staffing[shift.id]
          const regularCount = counts?.regular_assigned_count ?? 0
          const understaffed = counts?.understaffed ?? regularCount < shift.required_staff_count
          return <article className={`card p-4 ${understaffed && shift.status !== 'CANCELLED' ? 'border-amber-400' : ''}`} key={shift.id}>
            <div className="flex justify-between gap-2"><strong>{shift.start_time.slice(0, 5)}–{shift.end_time.slice(0, 5)}</strong><span className="text-xs font-semibold">{shift.status}</span></div>
            <h3 className="mt-2 font-semibold">{shift.shift_title}</h3>
            <p className="mt-2 text-sm">{locationName(shift.location_id)}</p><p className="text-sm">{activityName(shift.activity_type_id)}</p>
            <p className={`mt-2 text-sm font-medium ${understaffed ? 'text-amber-800' : 'text-green-800'}`}>{regularCount}/{counts?.required_staff_count ?? shift.required_staff_count} regular assigned {understaffed && '· Understaffed'}{counts?.shadowing_count ? ` · ${counts.shadowing_count} shadowing` : ''}</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <button className="button-secondary min-h-9 px-2 py-1 text-xs" onClick={() => setSelected(shift.id)}>Manage</button>
              {shift.status === 'DRAFT' && <button className="button-secondary min-h-9 px-2 py-1 text-xs" onClick={() => edit(shift)}>Edit</button>}
              <button className="button-secondary min-h-9 px-2 py-1 text-xs" onClick={() => void copy(shift)}>Copy</button>
              {shift.status === 'DRAFT' && <button className="button-secondary min-h-9 px-2 py-1 text-xs" onClick={() => void status(shift, 'PUBLISHED')}>Publish</button>}
              {shift.status === 'PUBLISHED' && <button className="button-secondary min-h-9 px-2 py-1 text-xs" onClick={() => void status(shift, 'DRAFT')}>Unpublish</button>}
              {shift.status !== 'CANCELLED' && <button className="button-secondary min-h-9 px-2 py-1 text-xs" onClick={() => void status(shift, 'CANCELLED')}>Cancel</button>}
            </div>
          </article>
        })}{filtered.every((item) => item.local_date !== day) && <p className="text-sm text-slate-500">No shifts</p>}</div>
      </section>)}
    </div>}

    {selectedShift && <section className="card mt-8" aria-labelledby="manage-heading">
      <div className="flex justify-between gap-4"><div><h2 id="manage-heading" className="text-xl font-semibold">Manage {displayDate(selectedShift.local_date)} shift</h2><p className="text-sm text-slate-600">Available eligible employees: {candidates.filter((item) => item.assignable_without_override).length}</p></div><button className="button-secondary" onClick={() => setSelected(null)}>Close</button></div>
      <h3 className="mt-5 font-semibold">Assigned employees</h3>
      {activeAssignments(selectedShift.id).length === 0 ? <EmptyState title="No employees assigned" /> : <ul className="mt-2 grid gap-2">{activeAssignments(selectedShift.id).map((item) => <li className="flex flex-wrap items-center justify-between gap-2 rounded-lg border p-3" key={item.id}><span>{name(item.staff_id)} · {item.assignment_kind === 'SHADOWING' ? 'Shadowing' : 'Regular'}</span><span className="flex gap-2"><button className="button-secondary" onClick={() => void replace(item)}>Replace</button><button className="button-secondary" onClick={() => void remove(item)}>Remove</button></span></li>)}</ul>}
      <h3 className="mt-6 font-semibold">Candidates</h3>
      <ul className="mt-2 grid gap-2 sm:grid-cols-2">{candidates.map((candidate) => <li className="rounded-lg border p-3" key={candidate.staff_id}><div className="flex flex-wrap justify-between gap-2"><strong>{candidate.full_name}</strong><span className="flex gap-2"><button className="button-secondary" disabled={candidate.conflicts.some((item) => !item.overridable)} onClick={() => void assign(candidate, 'REGULAR')}>Assign regular</button><button className="button-secondary" disabled={candidate.conflicts.some((item) => !item.overridable)} onClick={() => void assign(candidate, 'SHADOWING')}>Assign shadowing</button></span></div>{candidate.conflicts.length === 0 ? <p className="mt-1 text-sm text-green-800">Eligible and fully available</p> : <ul className="mt-2 list-disc pl-5 text-sm text-amber-900">{candidate.conflicts.map((item) => <li key={item.code}><strong>{item.code}</strong>: {item.message}{!item.overridable && ' (cannot override)'}</li>)}</ul>}</li>)}</ul>
    </section>}
  </div>
}
