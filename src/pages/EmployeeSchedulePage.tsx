import { useMemo, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { EmptyState, ErrorState, LoadingState } from '../components/States'
import {
  addScheduleDays,
  displayScheduleDate,
  displayScheduleTime,
  scheduleWeekStart,
  todayMelbourne,
} from '../domain/schedule'
import { supabase } from '../lib/supabase'
import type { EmployeeScheduleItem } from '../lib/types'
import { useEmployeeSchedule } from './useEmployeeSchedule'

export function ScheduleCard({ item }: { item: EmployeeScheduleItem }) {
  return (
    <article className="card" data-testid="schedule-card">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="text-sm font-medium text-blue-800">{displayScheduleDate(item.local_date)}</p>
          <h2 className="mt-1 text-lg font-semibold">{item.shift_title}</h2>
        </div>
        <span className="rounded-full bg-blue-50 px-2 py-1 text-xs font-semibold text-blue-900">
          {item.assignment_status === 'ASSIGNED' ? 'Assigned' : item.assignment_status}
        </span>
      </div>
      <dl className="mt-4 grid gap-2 text-sm sm:grid-cols-2">
        <div><dt className="text-slate-500">Time</dt><dd className="font-medium">{displayScheduleTime(item.start_time)}–{displayScheduleTime(item.end_time)}</dd></div>
        <div><dt className="text-slate-500">Location</dt><dd className="font-medium">{item.location_name}</dd></div>
        <div><dt className="text-slate-500">Activity</dt><dd className="font-medium">{item.activity_name}</dd></div>
        <div><dt className="text-slate-500">Acknowledgement</dt><dd className="font-medium">{item.acknowledged_at ? 'Acknowledged' : 'Outstanding'}</dd></div>
      </dl>
      <Link className="button-secondary mt-4 w-full sm:w-auto" to={`/employee/shifts/${item.shift_id}`}>View shift details</Link>
    </article>
  )
}

export function EmployeeSchedulePage() {
  const currentWeek = scheduleWeekStart(todayMelbourne())
  const [week, setWeek] = useState(currentWeek)
  const { items, loading, error, load } = useEmployeeSchedule()
  const weekEnd = addScheduleDays(week, 6)
  const visible = useMemo(
    () => items.filter((item) => item.local_date >= week && item.local_date <= weekEnd),
    [items, week, weekEnd],
  )

  return (
    <div>
      <h1 className="text-3xl font-bold">My Schedule</h1>
      <p className="mt-2 text-slate-600">Published shifts assigned to you. Times use Australia/Melbourne.</p>
      <div className="card mt-6 flex flex-wrap items-center justify-between gap-3">
        <button className="button-secondary" onClick={() => setWeek(addScheduleDays(week, -7))}>Previous week</button>
        <strong>{displayScheduleDate(week, true)} – {displayScheduleDate(weekEnd, true)}</strong>
        <button className="button-secondary" onClick={() => setWeek(addScheduleDays(week, 7))}>Next week</button>
      </div>
      {loading ? <div className="mt-6"><LoadingState label="Loading your schedule…" /></div>
        : error ? <div className="mt-6"><ErrorState message={error} retry={() => void load()} /></div>
          : visible.length === 0
            ? <div className="mt-6"><EmptyState title="No published shifts this week">Use previous or next week to check another week.</EmptyState></div>
            : <div className="mt-6 grid gap-4 md:grid-cols-2">{visible.map((item) => <ScheduleCard item={item} key={item.assignment_id} />)}</div>}
    </div>
  )
}

export function EmployeeShiftDetailsPage() {
  const { shiftId } = useParams()
  const navigate = useNavigate()
  const { items, loading, error, load } = useEmployeeSchedule()
  const [saving, setSaving] = useState(false)
  const [actionError, setActionError] = useState<string | null>(null)
  const item = items.find((candidate) => candidate.shift_id === shiftId)

  async function acknowledge() {
    if (!item) return
    setSaving(true)
    setActionError(null)
    const result = await supabase.rpc('acknowledge_assignment', { p_assignment_id: item.assignment_id })
    setSaving(false)
    if (result.error) {
      setActionError(result.error.message)
      return
    }
    await load()
  }

  if (loading) return <LoadingState label="Loading shift details…" />
  if (error) return <ErrorState message={error} retry={() => void load()} />
  if (!item) return <EmptyState title="Shift unavailable"><p>This shift is no longer active and published, or it is not assigned to you.</p><button className="button-secondary mt-4" onClick={() => navigate('/employee/schedule')}>Back to My Schedule</button></EmptyState>

  return (
    <div>
      <Link className="text-sm font-semibold text-blue-800 hover:underline" to="/employee/schedule">← My Schedule</Link>
      <div className="card mt-4">
        <p className="text-sm font-medium text-blue-800">{displayScheduleDate(item.local_date, true)}</p>
        <h1 className="mt-1 text-3xl font-bold">{item.shift_title}</h1>
        <dl className="mt-6 grid gap-4 sm:grid-cols-2">
          <div><dt className="text-sm text-slate-500">Time</dt><dd className="font-medium">{displayScheduleTime(item.start_time)}–{displayScheduleTime(item.end_time)}</dd></div>
          <div><dt className="text-sm text-slate-500">Location</dt><dd className="font-medium">{item.location_name}</dd></div>
          <div><dt className="text-sm text-slate-500">Activity</dt><dd className="font-medium">{item.activity_name}</dd></div>
          <div><dt className="text-sm text-slate-500">Assignment status</dt><dd className="font-medium">Assigned ({item.assignment_kind === 'SHADOWING' ? 'shadowing' : 'regular'})</dd></div>
          <div className="sm:col-span-2"><dt className="text-sm text-slate-500">Notes</dt><dd className="font-medium">{item.notes?.trim() || 'No notes provided.'}</dd></div>
          <div className="sm:col-span-2"><dt className="text-sm text-slate-500">Other assigned staff</dt><dd className="font-medium">{item.colleague_names.length ? item.colleague_names.join(', ') : 'No other staff assigned.'}</dd></div>
        </dl>
        <section className="mt-6 border-t pt-5" aria-labelledby="acknowledgement-heading">
          <h2 className="text-lg font-semibold" id="acknowledgement-heading">Acknowledgement</h2>
          {item.acknowledged_at
            ? <p className="mt-2 text-green-800">Acknowledged {new Intl.DateTimeFormat('en-AU', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Australia/Melbourne' }).format(new Date(item.acknowledged_at))}.</p>
            : <><p className="mt-2 text-slate-600">Confirm that you have seen this assignment.</p><button className="button mt-4" disabled={saving} onClick={() => void acknowledge()}>{saving ? 'Acknowledging…' : 'Acknowledge shift'}</button></>}
          {actionError && <p className="mt-3 text-red-800" role="alert">{actionError}</p>}
        </section>
      </div>
    </div>
  )
}
