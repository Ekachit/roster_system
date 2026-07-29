import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { EmptyState, ErrorState, LoadingState } from '../components/States'
import { ISO_WEEKDAYS, ROSTER_TIME_ZONE } from '../domain/availability'
import { supabase } from '../lib/supabase'
import type { AvailabilityException, AvailabilityKind, RecurringAvailability, StaffRecord } from '../lib/types'

const melbourneToday = () => new Intl.DateTimeFormat('en-CA', {
  timeZone: ROSTER_TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
}).format(new Date())
const timeText = (value: string | null) => value?.slice(0, 5) ?? ''
const recurringInitial = () => ({ weekday: 1, start_time: '09:00', end_time: '17:00', effective_start_date: melbourneToday(), effective_end_date: '', note: '' })
const exceptionInitial = () => ({ local_date: melbourneToday(), kind: 'unavailable' as AvailabilityKind, start_time: '09:00', end_time: '17:00', is_full_day: false, note: '' })

function validateRange(start: string, end: string) {
  return start && end && end > start ? null : 'End time must be later than start time.'
}

export function EmployeeAvailabilityPage() {
  const [recurring, setRecurring] = useState<RecurringAvailability[]>([])
  const [exceptions, setExceptions] = useState<AvailabilityException[]>([])
  const [recurringForm, setRecurringForm] = useState(recurringInitial)
  const [exceptionForm, setExceptionForm] = useState(exceptionInitial)
  const [editingRecurring, setEditingRecurring] = useState<string | null>(null)
  const [editingException, setEditingException] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    const [rules, dates] = await Promise.all([
      supabase.from('recurring_availability').select('*').order('weekday').order('start_time'),
      supabase.from('availability_exceptions').select('*').order('local_date').order('start_time'),
    ])
    setRecurring((rules.data as RecurringAvailability[] | null) ?? [])
    setExceptions((dates.data as AvailabilityException[] | null) ?? [])
    setError((rules.error ?? dates.error)?.message ?? null)
    setLoading(false)
  }, [])
  useEffect(() => { void load() }, [load])

  async function saveRecurring(event: FormEvent) {
    event.preventDefault(); setError(null); setMessage(null)
    const validation = validateRange(recurringForm.start_time, recurringForm.end_time)
    if (validation) return setError(validation)
    if (recurringForm.effective_end_date && recurringForm.effective_end_date < recurringForm.effective_start_date) {
      return setError('Effective end date cannot be before the start date.')
    }
    setSaving(true)
    const { error: saveError } = await supabase.rpc('save_recurring_availability', {
      p_id: editingRecurring, p_weekday: recurringForm.weekday,
      p_start_time: recurringForm.start_time, p_end_time: recurringForm.end_time,
      p_effective_start_date: recurringForm.effective_start_date,
      p_effective_end_date: recurringForm.effective_end_date || null, p_note: recurringForm.note,
    })
    setSaving(false)
    if (saveError) return setError(saveError.message)
    setMessage(editingRecurring ? 'Recurring availability updated.' : 'Recurring availability saved.')
    setEditingRecurring(null); setRecurringForm(recurringInitial()); await load()
  }

  async function saveException(event: FormEvent) {
    event.preventDefault(); setError(null); setMessage(null)
    if (!exceptionForm.is_full_day) {
      const validation = validateRange(exceptionForm.start_time, exceptionForm.end_time)
      if (validation) return setError(validation)
    }
    setSaving(true)
    const { error: saveError } = await supabase.rpc('save_availability_exception', {
      p_id: editingException, p_local_date: exceptionForm.local_date, p_kind: exceptionForm.kind,
      p_start_time: exceptionForm.is_full_day ? null : exceptionForm.start_time,
      p_end_time: exceptionForm.is_full_day ? null : exceptionForm.end_time,
      p_is_full_day: exceptionForm.is_full_day, p_note: exceptionForm.note,
    })
    setSaving(false)
    if (saveError) return setError(saveError.message)
    setMessage(editingException ? 'Date exception updated.' : 'Date exception saved.')
    setEditingException(null); setExceptionForm(exceptionInitial()); await load()
  }

  async function remove(kind: 'recurring' | 'exception', id: string) {
    if (!window.confirm(`Delete this ${kind === 'recurring' ? 'recurring rule' : 'date exception'}?`)) return
    setError(null); setMessage(null)
    const result = await supabase.rpc(kind === 'recurring' ? 'delete_recurring_availability' : 'delete_availability_exception', { p_id: id })
    if (result.error) return setError(result.error.message)
    setMessage(kind === 'recurring' ? 'Recurring availability deleted.' : 'Date exception deleted.')
    await load()
  }

  function editRule(rule: RecurringAvailability) {
    setEditingRecurring(rule.id)
    setRecurringForm({
      weekday: rule.weekday, start_time: timeText(rule.start_time), end_time: timeText(rule.end_time),
      effective_start_date: rule.effective_start_date, effective_end_date: rule.effective_end_date ?? '', note: rule.note ?? '',
    })
  }
  function editDate(item: AvailabilityException) {
    setEditingException(item.id)
    setExceptionForm({
      local_date: item.local_date, kind: item.kind, start_time: timeText(item.start_time) || '09:00',
      end_time: timeText(item.end_time) || '17:00', is_full_day: item.is_full_day, note: item.note ?? '',
    })
  }

  return <div>
    <h1 className="text-3xl font-bold">My availability</h1>
    <p className="mt-2 text-slate-600">Times are interpreted in {ROSTER_TIME_ZONE}. Recurring rules describe your usual week. One-off date exceptions override them only for the specified date and time.</p>
    {message && <p className="mt-4 rounded-lg bg-green-50 p-3 text-green-900" role="status">{message}</p>}
    {error && <div className="mt-4"><ErrorState message={error} retry={() => void load()} /></div>}

    <section className="mt-8" aria-labelledby="recurring-heading">
      <h2 id="recurring-heading" className="text-2xl font-semibold">Recurring weekly availability</h2>
      <form className="card mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4" onSubmit={saveRecurring}>
        <label className="font-medium">Weekday<select className="field" value={recurringForm.weekday} onChange={(e) => setRecurringForm({ ...recurringForm, weekday: Number(e.target.value) })}>{ISO_WEEKDAYS.slice(1).map((day, index) => <option value={index + 1} key={day}>{day}</option>)}</select></label>
        <label className="font-medium">Start time<input className="field" type="time" required value={recurringForm.start_time} onChange={(e) => setRecurringForm({ ...recurringForm, start_time: e.target.value })} /></label>
        <label className="font-medium">End time<input className="field" type="time" required value={recurringForm.end_time} onChange={(e) => setRecurringForm({ ...recurringForm, end_time: e.target.value })} /></label>
        <label className="font-medium">Effective from<input className="field" type="date" required value={recurringForm.effective_start_date} onChange={(e) => setRecurringForm({ ...recurringForm, effective_start_date: e.target.value })} /></label>
        <label className="font-medium">Effective until (optional)<input className="field" type="date" value={recurringForm.effective_end_date} onChange={(e) => setRecurringForm({ ...recurringForm, effective_end_date: e.target.value })} /></label>
        <label className="font-medium sm:col-span-2 lg:col-span-3">Note (optional)<input className="field" maxLength={500} value={recurringForm.note} onChange={(e) => setRecurringForm({ ...recurringForm, note: e.target.value })} /></label>
        <div className="flex gap-2 lg:col-span-4"><button className="button" disabled={saving}>{saving ? 'Saving…' : editingRecurring ? 'Update rule' : 'Add recurring rule'}</button>{editingRecurring && <button type="button" className="button-secondary" onClick={() => { setEditingRecurring(null); setRecurringForm(recurringInitial()) }}>Cancel</button>}</div>
      </form>
      <AvailabilityList loading={loading} empty="No recurring availability yet. You are unavailable unless a date-specific available exception applies.">
        {recurring.map((rule) => <li className="card" key={rule.id}><div className="flex flex-wrap justify-between gap-3"><div><span className="rounded-full bg-blue-100 px-2 py-1 text-xs font-semibold text-blue-900">Recurring</span><h3 className="mt-2 font-semibold">{ISO_WEEKDAYS[rule.weekday]} · {timeText(rule.start_time)}–{timeText(rule.end_time)}</h3><p className="text-sm text-slate-600">{rule.effective_start_date} to {rule.effective_end_date ?? 'ongoing'}{rule.note ? ` · ${rule.note}` : ''}</p></div><div className="flex gap-2"><button className="button-secondary" onClick={() => editRule(rule)}>Edit</button><button className="button-secondary" onClick={() => void remove('recurring', rule.id)}>Delete</button></div></div></li>)}
      </AvailabilityList>
    </section>

    <section className="mt-10" aria-labelledby="exceptions-heading">
      <h2 id="exceptions-heading" className="text-2xl font-semibold">One-off date exceptions</h2>
      <form className="card mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4" onSubmit={saveException}>
        <label className="font-medium">Date<input className="field" type="date" required value={exceptionForm.local_date} onChange={(e) => setExceptionForm({ ...exceptionForm, local_date: e.target.value })} /></label>
        <label className="font-medium">Status<select className="field" value={exceptionForm.kind} onChange={(e) => setExceptionForm({ ...exceptionForm, kind: e.target.value as AvailabilityKind, is_full_day: e.target.value === 'available' ? false : exceptionForm.is_full_day })}><option value="unavailable">Unavailable</option><option value="available">Available</option></select></label>
        <label className="flex items-center gap-2 font-medium"><input type="checkbox" checked={exceptionForm.is_full_day} disabled={exceptionForm.kind === 'available'} onChange={(e) => setExceptionForm({ ...exceptionForm, is_full_day: e.target.checked })} />Unavailable all day</label>
        <div />
        {!exceptionForm.is_full_day && <><label className="font-medium">Start time<input className="field" type="time" required value={exceptionForm.start_time} onChange={(e) => setExceptionForm({ ...exceptionForm, start_time: e.target.value })} /></label><label className="font-medium">End time<input className="field" type="time" required value={exceptionForm.end_time} onChange={(e) => setExceptionForm({ ...exceptionForm, end_time: e.target.value })} /></label></>}
        <label className="font-medium sm:col-span-2">Note (optional)<input className="field" maxLength={500} value={exceptionForm.note} onChange={(e) => setExceptionForm({ ...exceptionForm, note: e.target.value })} /></label>
        <div className="flex gap-2 lg:col-span-4"><button className="button" disabled={saving}>{saving ? 'Saving…' : editingException ? 'Update exception' : 'Add date exception'}</button>{editingException && <button type="button" className="button-secondary" onClick={() => { setEditingException(null); setExceptionForm(exceptionInitial()) }}>Cancel</button>}</div>
      </form>
      <AvailabilityList loading={loading} empty="No date-specific exceptions.">
        {exceptions.map((item) => <li className="card" key={item.id}><div className="flex flex-wrap justify-between gap-3"><div><span className={`rounded-full px-2 py-1 text-xs font-semibold ${item.kind === 'available' ? 'bg-green-100 text-green-900' : 'bg-amber-100 text-amber-900'}`}>One-off · {item.kind}</span><h3 className="mt-2 font-semibold">{item.local_date} · {item.is_full_day ? 'All day' : `${timeText(item.start_time)}–${timeText(item.end_time)}`}</h3>{item.note && <p className="text-sm text-slate-600">{item.note}</p>}</div><div className="flex gap-2"><button className="button-secondary" onClick={() => editDate(item)}>Edit</button><button className="button-secondary" onClick={() => void remove('exception', item.id)}>Delete</button></div></div></li>)}
      </AvailabilityList>
    </section>
  </div>
}

function AvailabilityList({ loading, empty, children }: { loading: boolean; empty: string; children: React.ReactNode }) {
  const count = Array.isArray(children) ? children.length : children ? 1 : 0
  return <div className="mt-4">{loading ? <LoadingState /> : count === 0 ? <EmptyState title={empty} /> : <ul className="grid gap-3">{children}</ul>}</div>
}

export function SupervisorAvailabilityPage() {
  const [staff, setStaff] = useState<StaffRecord[]>([])
  const [recurring, setRecurring] = useState<RecurringAvailability[]>([])
  const [exceptions, setExceptions] = useState<AvailabilityException[]>([])
  const [employeeId, setEmployeeId] = useState('')
  const [date, setDate] = useState('')
  const [weekday, setWeekday] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const load = useCallback(async () => {
    setLoading(true)
    const [people, rules, dates] = await Promise.all([
      supabase.from('supervisor_staff_directory').select('*').eq('is_active', true).order('full_name'),
      supabase.from('recurring_availability').select('*').order('weekday').order('start_time'),
      supabase.from('availability_exceptions').select('*').order('local_date').order('start_time'),
    ])
    setStaff((people.data as StaffRecord[] | null) ?? [])
    setRecurring((rules.data as RecurringAvailability[] | null) ?? [])
    setExceptions((dates.data as AvailabilityException[] | null) ?? [])
    setError((people.error ?? rules.error ?? dates.error)?.message ?? null)
    setLoading(false)
  }, [])
  useEffect(() => { void load() }, [load])
  const name = useCallback((id: string) => staff.find((person) => person.id === id)?.full_name ?? 'Unknown employee', [staff])
  const dateWeekday = date ? new Date(`${date}T12:00:00Z`).getUTCDay() || 7 : null
  const filteredRules = useMemo(() => recurring.filter((rule) =>
    (!employeeId || rule.staff_id === employeeId) && (!weekday || rule.weekday === Number(weekday))
    && (!date || (rule.weekday === dateWeekday && rule.effective_start_date <= date && (!rule.effective_end_date || rule.effective_end_date >= date)))
  ), [date, dateWeekday, employeeId, recurring, weekday])
  const filteredExceptions = useMemo(() => exceptions.filter((item) =>
    (!employeeId || item.staff_id === employeeId) && (!date || item.local_date === date)
    && (!weekday || (new Date(`${item.local_date}T12:00:00Z`).getUTCDay() || 7) === Number(weekday))
  ), [date, employeeId, exceptions, weekday])

  return <div><h1 className="text-3xl font-bold">Staff availability</h1><p className="mt-2 text-slate-600">Read-only availability for active employees. Recurring weekly rules and overriding one-off exceptions are shown separately in {ROSTER_TIME_ZONE}.</p>
    {error && <div className="mt-4"><ErrorState message={error} retry={() => void load()} /></div>}
    <div className="card mt-6 grid gap-4 sm:grid-cols-3"><label className="font-medium">Employee<select className="field" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)}><option value="">All active employees</option>{staff.map((person) => <option key={person.id} value={person.id}>{person.full_name}</option>)}</select></label><label className="font-medium">Date<input className="field" type="date" value={date} onChange={(e) => setDate(e.target.value)} /></label><label className="font-medium">Weekday<select className="field" value={weekday} onChange={(e) => setWeekday(e.target.value)}><option value="">All weekdays</option>{ISO_WEEKDAYS.slice(1).map((day, index) => <option key={day} value={index + 1}>{day}</option>)}</select></label></div>
    {loading ? <div className="mt-6"><LoadingState /></div> : filteredRules.length + filteredExceptions.length === 0 ? <div className="mt-6"><EmptyState title="No availability matches these filters" /></div> : <div className="mt-6 grid gap-6 lg:grid-cols-2"><section><h2 className="text-xl font-semibold">Recurring rules</h2><ul className="mt-3 grid gap-3">{filteredRules.map((rule) => <li className="card" key={rule.id}><span className="rounded-full bg-blue-100 px-2 py-1 text-xs font-semibold text-blue-900">Recurring</span><h3 className="mt-2 font-semibold">{name(rule.staff_id)}</h3><p>{ISO_WEEKDAYS[rule.weekday]} · {timeText(rule.start_time)}–{timeText(rule.end_time)}</p><p className="text-sm text-slate-600">{rule.effective_start_date} to {rule.effective_end_date ?? 'ongoing'}{rule.note ? ` · ${rule.note}` : ''}</p></li>)}</ul></section><section><h2 className="text-xl font-semibold">One-off exceptions</h2><ul className="mt-3 grid gap-3">{filteredExceptions.map((item) => <li className="card" key={item.id}><span className={`rounded-full px-2 py-1 text-xs font-semibold ${item.kind === 'available' ? 'bg-green-100 text-green-900' : 'bg-amber-100 text-amber-900'}`}>One-off · {item.kind}</span><h3 className="mt-2 font-semibold">{name(item.staff_id)}</h3><p>{item.local_date} · {item.is_full_day ? 'All day' : `${timeText(item.start_time)}–${timeText(item.end_time)}`}</p>{item.note && <p className="text-sm text-slate-600">{item.note}</p>}</li>)}</ul></section></div>}
  </div>
}
