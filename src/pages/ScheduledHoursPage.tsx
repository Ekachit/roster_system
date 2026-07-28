import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { EmptyState, ErrorState, LoadingState } from '../components/States'
import { ROSTER_TIME_ZONE } from '../domain/availability'
import {
  displayScheduleDate,
  melbourneScheduleWeek,
} from '../domain/schedule'
import {
  formatDurationMinutes,
  scheduledHoursCsv,
  scheduledHoursFilename,
} from '../domain/reporting'
import { supabase } from '../lib/supabase'
import type { ScheduledHoursRow } from '../lib/types'

interface ReportFilters {
  startDate: string
  endDate: string
  staffId: string
  locationId: string
  activityTypeId: string
}

interface FilterOption {
  id: string
  name: string
}

interface EmployeeOption {
  id: string
  full_name: string
  role: 'supervisor' | 'employee'
}

function initialFilters(): ReportFilters {
  const { startDate, endDate } = melbourneScheduleWeek()
  return {
    startDate,
    endDate,
    staffId: '',
    locationId: '',
    activityTypeId: '',
  }
}

function displayStatus(status: string) {
  return status[0] + status.slice(1).toLowerCase()
}

function downloadCsv(rows: ScheduledHoursRow[], filters: ReportFilters) {
  const blob = new Blob([scheduledHoursCsv(rows)], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = scheduledHoursFilename(filters.startDate, filters.endDate)
  document.body.append(link)
  link.click()
  link.remove()
  URL.revokeObjectURL(url)
}

export function ReportResults({ rows }: { rows: ScheduledHoursRow[] }) {
  const groups = useMemo(() => {
    const grouped = new Map<string, ScheduledHoursRow[]>()
    for (const row of rows) {
      grouped.set(row.staff_id, [...(grouped.get(row.staff_id) ?? []), row])
    }
    return [...grouped.values()]
  }, [rows])

  if (rows.length === 0) {
    return (
      <EmptyState title="No scheduled hours match these filters">
        Cancelled shifts and removed assignments are not included.
      </EmptyState>
    )
  }

  return (
    <div className="grid min-w-0 gap-6">
      <div className="min-w-0 overflow-x-auto rounded-xl border border-slate-200 bg-white shadow-sm">
        <table className="min-w-full text-left text-sm">
          <thead className="bg-slate-50">
            <tr>
              <th className="px-4 py-3 font-semibold">Employee</th>
              <th className="px-4 py-3 font-semibold">Shift count</th>
              <th className="px-4 py-3 font-semibold">Total scheduled hours</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-200">
            {groups.map((employeeRows) => (
              <tr key={employeeRows[0].staff_id}>
                <td className="px-4 py-3 font-medium">{employeeRows[0].employee_name}</td>
                <td className="px-4 py-3">{employeeRows.length}</td>
                <td className="px-4 py-3">
                  {formatDurationMinutes(employeeRows.reduce(
                    (total, row) => total + row.duration_minutes,
                    0,
                  ))}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {groups.map((employeeRows) => (
        <section className="card min-w-0" key={employeeRows[0].staff_id}>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 className="text-xl font-semibold">{employeeRows[0].employee_name}</h2>
              <p className="text-sm text-slate-600">
                {employeeRows.length} {employeeRows.length === 1 ? 'shift' : 'shifts'} ·{' '}
                {formatDurationMinutes(employeeRows.reduce(
                  (total, row) => total + row.duration_minutes,
                  0,
                ))}
              </p>
            </div>
            <span className="rounded-full bg-green-100 px-3 py-1 text-xs font-semibold text-green-900">
              Active scheduled assignments
            </span>
          </div>

          <div className="mt-4 overflow-x-auto">
            <table className="min-w-full text-left text-sm">
              <thead className="border-b border-slate-200 text-slate-600">
                <tr>
                  <th className="px-2 py-2 font-medium">Date</th>
                  <th className="px-2 py-2 font-medium">Time</th>
                  <th className="px-2 py-2 font-medium">Duration</th>
                  <th className="px-2 py-2 font-medium">Location</th>
                  <th className="px-2 py-2 font-medium">Activity type</th>
                  <th className="px-2 py-2 font-medium">Shift status</th>
                  <th className="px-2 py-2 font-medium">Assignment status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-100">
                {employeeRows.map((row) => (
                  <tr key={row.assignment_id}>
                    <td className="whitespace-nowrap px-2 py-3">
                      {displayScheduleDate(row.local_date, true)}
                    </td>
                    <td className="whitespace-nowrap px-2 py-3">
                      {row.start_time.slice(0, 5)}–{row.end_time.slice(0, 5)}
                    </td>
                    <td className="whitespace-nowrap px-2 py-3">
                      {formatDurationMinutes(row.duration_minutes)}
                    </td>
                    <td className="px-2 py-3">{row.location_name}</td>
                    <td className="px-2 py-3">{row.activity_name}</td>
                    <td className="px-2 py-3">{displayStatus(row.shift_status)}</td>
                    <td className="px-2 py-3">{displayStatus(row.assignment_status)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ))}
    </div>
  )
}

export function ReportExplanation() {
  return (
    <>
      <p className="mt-2 text-slate-600">
        This report shows current scheduled hours for published shifts with active assignments.
        It does not represent attendance, actual worked hours or payroll. Dates and times use{' '}
        {ROSTER_TIME_ZONE}.
      </p>
      <p className="mt-2 text-sm text-slate-600">
        Removed assignments are excluded. If someone is removed after becoming sick or leaving
        early, they will not contribute hours here; the historical removal remains available in
        audit history. Actual worked duration requires a future attendance-confirmation workflow.
      </p>
    </>
  )
}

export function ScheduledHoursPage() {
  const [filters, setFilters] = useState<ReportFilters>(initialFilters)
  const [appliedFilters, setAppliedFilters] = useState<ReportFilters>(initialFilters)
  const [rows, setRows] = useState<ScheduledHoursRow[]>([])
  const [employees, setEmployees] = useState<EmployeeOption[]>([])
  const [locations, setLocations] = useState<FilterOption[]>([])
  const [activities, setActivities] = useState<FilterOption[]>([])
  const [loading, setLoading] = useState(true)
  const [reportError, setReportError] = useState<string | null>(null)
  const [filterError, setFilterError] = useState<string | null>(null)

  const loadReport = useCallback(async (selected: ReportFilters) => {
    setLoading(true)
    setReportError(null)
    const result = await supabase.rpc('scheduled_hours_report', {
      p_start_date: selected.startDate,
      p_end_date: selected.endDate,
      p_staff_id: selected.staffId || null,
      p_location_id: selected.locationId || null,
      p_activity_type_id: selected.activityTypeId || null,
    })
    setRows((result.data as ScheduledHoursRow[] | null) ?? [])
    setReportError(result.error?.message ?? null)
    setLoading(false)
  }, [])

  useEffect(() => {
    void Promise.all([
      supabase.from('supervisor_staff_directory').select('id, full_name, role').order('full_name'),
      supabase.from('locations').select('id, name').order('name'),
      supabase.from('activity_types').select('id, name').order('name'),
    ]).then(([staffResult, locationResult, activityResult]) => {
      setEmployees(
        ((staffResult.data as EmployeeOption[] | null) ?? [])
          .filter((employee) => employee.role === 'employee'),
      )
      setLocations((locationResult.data as FilterOption[] | null) ?? [])
      setActivities((activityResult.data as FilterOption[] | null) ?? [])
      const loadError = staffResult.error ?? locationResult.error ?? activityResult.error
      setFilterError(loadError?.message ?? null)
    })
  }, [])

  useEffect(() => {
    void loadReport(appliedFilters)
  }, [appliedFilters, loadReport])

  function applyFilters(event: FormEvent) {
    event.preventDefault()
    if (filters.startDate > filters.endDate) {
      setReportError('Start date must be on or before end date.')
      return
    }
    setAppliedFilters({ ...filters })
  }

  const filtersChanged = JSON.stringify(filters) !== JSON.stringify(appliedFilters)

  return (
    <div className="min-w-0">
      <h1 className="text-3xl font-bold">Scheduled hours</h1>
      <ReportExplanation />

      <form className="card mt-6 grid min-w-0 gap-4 sm:grid-cols-2 lg:grid-cols-5" onSubmit={applyFilters}>
        <label className="min-w-0 font-medium">
          Start date
          <input
            className="field"
            type="date"
            required
            value={filters.startDate}
            onChange={(event) => setFilters({ ...filters, startDate: event.target.value })}
          />
        </label>
        <label className="min-w-0 font-medium">
          End date
          <input
            className="field"
            type="date"
            required
            value={filters.endDate}
            onChange={(event) => setFilters({ ...filters, endDate: event.target.value })}
          />
        </label>
        <label className="min-w-0 font-medium">
          Employee
          <select
            className="field min-w-0"
            value={filters.staffId}
            onChange={(event) => setFilters({ ...filters, staffId: event.target.value })}
          >
            <option value="">All employees</option>
            {employees.map((employee) => (
              <option key={employee.id} value={employee.id}>{employee.full_name}</option>
            ))}
          </select>
        </label>
        <label className="min-w-0 font-medium">
          Location
          <select
            className="field min-w-0"
            value={filters.locationId}
            onChange={(event) => setFilters({ ...filters, locationId: event.target.value })}
          >
            <option value="">All locations</option>
            {locations.map((location) => (
              <option key={location.id} value={location.id}>{location.name}</option>
            ))}
          </select>
        </label>
        <label className="min-w-0 font-medium">
          Activity type
          <select
            className="field min-w-0"
            value={filters.activityTypeId}
            onChange={(event) => setFilters({ ...filters, activityTypeId: event.target.value })}
          >
            <option value="">All activity types</option>
            {activities.map((activity) => (
              <option key={activity.id} value={activity.id}>{activity.name}</option>
            ))}
          </select>
        </label>
        <div className="flex flex-wrap gap-3 sm:col-span-2 lg:col-span-5">
          <button className="button" type="submit">Run report</button>
          <button
            className="button-secondary"
            type="button"
            disabled={loading || rows.length === 0 || filtersChanged}
            onClick={() => downloadCsv(rows, appliedFilters)}
          >
            Export CSV
          </button>
          {filtersChanged && (
            <p className="self-center text-sm text-amber-800">
              Run the report to apply changed filters before exporting.
            </p>
          )}
          <p className="w-full text-sm text-slate-600">
            CSV export contains the same current scheduled-hours rows produced by the applied
            filters.
          </p>
        </div>
      </form>

      {filterError && <div className="mt-6"><ErrorState message={filterError} /></div>}
      {reportError && <div className="mt-6"><ErrorState message={reportError} retry={() => void loadReport(appliedFilters)} /></div>}

      <div className="mt-6">
        {loading
          ? <LoadingState label="Loading scheduled hours…" />
          : <ReportResults rows={rows} />}
      </div>
    </div>
  )
}
