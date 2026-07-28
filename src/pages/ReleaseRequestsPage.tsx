import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { EmptyState, ErrorState, LoadingState } from '../components/States'
import { ReleaseRequestStatusBadge } from '../components/ReleaseRequestStatusBadge'
import { ROSTER_TIME_ZONE } from '../domain/availability'
import { supabase } from '../lib/supabase'
import type {
  EmployeeReleaseRequest,
  ReleaseRequestAssignment,
  ReleaseCandidate,
  ReleaseRequestStatus,
  SupervisorReleaseRequest,
} from '../lib/types'

function displayShiftDate(date: string) {
  return new Intl.DateTimeFormat('en-AU', {
    timeZone: ROSTER_TIME_ZONE,
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  }).format(new Date(`${date}T12:00:00Z`))
}

function displayTimestamp(timestamp: string) {
  return new Intl.DateTimeFormat('en-AU', {
    timeZone: ROSTER_TIME_ZONE,
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(timestamp))
}

function shiftSummary(request: Pick<EmployeeReleaseRequest, 'local_date' | 'start_time' | 'end_time' | 'location_name' | 'activity_name'>) {
  return `${displayShiftDate(request.local_date)} · ${request.start_time.slice(0, 5)}–${request.end_time.slice(0, 5)} · ${request.location_name} · ${request.activity_name}`
}

export function EmployeeReleaseRequestsPage() {
  const [requests, setRequests] = useState<EmployeeReleaseRequest[]>([])
  const [requestableAssignments, setRequestableAssignments] = useState<ReleaseRequestAssignment[]>([])
  const [assignmentId, setAssignmentId] = useState('')
  const [reason, setReason] = useState('')
  const [note, setNote] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    const [requestRows, assignmentRows] = await Promise.all([
      supabase.rpc('employee_release_requests'),
      supabase.rpc('employee_release_request_assignments'),
    ])
    setRequests((requestRows.data as EmployeeReleaseRequest[] | null) ?? [])
    setRequestableAssignments((assignmentRows.data as ReleaseRequestAssignment[] | null) ?? [])
    setError((requestRows.error ?? assignmentRows.error)?.message ?? null)
    setLoading(false)
  }, [])

  useEffect(() => { void load() }, [load])

  async function submit(event: FormEvent) {
    event.preventDefault()
    setError(null)
    setMessage(null)
    if (!window.confirm('Submit this release request? You remain assigned until a supervisor approves it.')) return
    setSaving(true)
    const result = await supabase.rpc('submit_release_request', {
      p_assignment_id: assignmentId,
      p_reason: reason,
      p_note: note,
    })
    setSaving(false)
    if (result.error) return setError(result.error.message)
    setAssignmentId('')
    setReason('')
    setNote('')
    setMessage('Request submitted. You remain assigned until a supervisor approves it.')
    await load()
  }

  return (
    <div>
      <h1 className="text-3xl font-bold">My release requests</h1>
      <p className="mt-2 text-slate-600">
        Ask to be released before a published shift or while it is in progress. If you become sick
        or need to leave early, submit the request before the shift ends. Times use {ROSTER_TIME_ZONE}.
      </p>
      {message && <p className="mt-4 rounded-lg bg-green-50 p-3 text-green-900" role="status">{message}</p>}
      {error && <div className="mt-4"><ErrorState message={error} retry={() => void load()} /></div>}

      <form className="card mt-6 grid gap-4" onSubmit={submit}>
        <h2 className="text-xl font-semibold">New request</h2>
        <p className="text-sm text-slate-600">
          Submitting does not remove you from the shift. Continue to treat the shift as assigned until it is approved.
        </p>
        <label className="font-medium">
          Assigned shift
          <select
            className="field"
            required
            value={assignmentId}
            onChange={(event) => setAssignmentId(event.target.value)}
          >
            <option value="">Select an active shift</option>
            {requestableAssignments.map((item) => (
              <option key={item.assignment_id} value={item.assignment_id}>
                {item.shift_title} · {item.local_date} · {item.start_time.slice(0, 5)}
              </option>
            ))}
          </select>
        </label>
        <label className="font-medium">
          Reason
          <input
            className="field"
            required
            maxLength={200}
            value={reason}
            onChange={(event) => setReason(event.target.value)}
          />
        </label>
        <label className="font-medium">
          Explanatory note (optional)
          <textarea
            className="field min-h-24"
            maxLength={1000}
            value={note}
            onChange={(event) => setNote(event.target.value)}
          />
        </label>
        <div>
          <button className="button" disabled={saving || requestableAssignments.length === 0}>
            {saving ? 'Submitting…' : 'Submit request'}
          </button>
        </div>
        {!loading && requestableAssignments.length === 0 && (
          <p className="text-sm text-slate-600">
            There are no published assignments still open for a release request.
          </p>
        )}
      </form>

      <section className="mt-8" aria-labelledby="request-history-heading">
        <h2 id="request-history-heading" className="text-xl font-semibold">Request history</h2>
        {loading ? <div className="mt-4"><LoadingState /></div> : requests.length === 0 ? (
          <EmptyState title="No release requests">Submitted requests and their outcomes will appear here.</EmptyState>
        ) : (
          <div className="mt-4 grid gap-4">
            {requests.map((request) => (
              <article className="card" key={request.request_id}>
                <div className="flex flex-wrap items-start justify-between gap-3">
                  <div>
                    <h3 className="font-semibold">{request.shift_title}</h3>
                    <p className="mt-1 text-sm text-slate-600">{shiftSummary(request)}</p>
                  </div>
                  <ReleaseRequestStatusBadge status={request.status} />
                </div>
                <dl className="mt-4 grid gap-2 text-sm sm:grid-cols-2">
                  <div><dt className="font-medium">Reason</dt><dd>{request.reason}</dd></div>
                  <div><dt className="font-medium">Submitted</dt><dd>{displayTimestamp(request.submitted_at)}</dd></div>
                  {request.note && <div><dt className="font-medium">Note</dt><dd>{request.note}</dd></div>}
                  {request.resolution_reason && (
                    <div><dt className="font-medium">Supervisor response</dt><dd>{request.resolution_reason}</dd></div>
                  )}
                </dl>
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}

export function SupervisorReleaseRequestsPage() {
  const [requests, setRequests] = useState<SupervisorReleaseRequest[]>([])
  const [filter, setFilter] = useState<ReleaseRequestStatus | 'ALL'>('PENDING')
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [candidates, setCandidates] = useState<ReleaseCandidate[]>([])
  const [replacementStaffId, setReplacementStaffId] = useState('')
  const [approvalReason, setApprovalReason] = useState('')
  const [overrideConfirmed, setOverrideConfirmed] = useState(false)
  const [overrideReason, setOverrideReason] = useState('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    const result = await supabase.rpc('supervisor_release_requests', { p_status: null })
    setRequests((result.data as SupervisorReleaseRequest[] | null) ?? [])
    setError(result.error?.message ?? null)
    setLoading(false)
  }, [])

  useEffect(() => { void load() }, [load])

  const selected = requests.find((request) => request.request_id === selectedId) ?? null
  useEffect(() => {
    setCandidates([])
    setReplacementStaffId('')
    setApprovalReason('')
    setOverrideConfirmed(false)
    setOverrideReason('')
    if (!selected || selected.status !== 'PENDING') return
    void supabase.rpc('release_request_candidates', { p_request_id: selected.request_id })
      .then((result) => {
        setCandidates((result.data as ReleaseCandidate[] | null) ?? [])
        if (result.error) setError(result.error.message)
      })
  }, [selected?.request_id, selected?.status]) // eslint-disable-line react-hooks/exhaustive-deps

  const filtered = requests.filter((request) => filter === 'ALL' || request.status === filter)
  const replacement = candidates.find((candidate) => candidate.staff_id === replacementStaffId)
  const hardConflict = replacement?.conflicts.some((conflict) => !conflict.overridable) ?? false
  const needsOverride = (replacement?.conflicts.length ?? 0) > 0

  async function reject() {
    if (!selected) return
    const reason = window.prompt('Why is this request being rejected?')
    if (!reason?.trim()) return
    if (!window.confirm(`Reject ${selected.employee_name}'s release request?`)) return
    await resolve('reject_release_request', {
      p_request_id: selected.request_id,
      p_rejection_reason: reason,
    }, 'Request rejected.')
  }

  async function approveRemoval() {
    if (!selected) return
    const reason = window.prompt('Approval and removal reason:')
    if (!reason?.trim()) return
    if (!window.confirm(`Approve this request and remove ${selected.employee_name} without a replacement?`)) return
    await resolve('approve_release_request_remove', {
      p_request_id: selected.request_id,
      p_approval_reason: reason,
    }, 'Request approved and employee removed.')
  }

  async function resolve(
    functionName: 'reject_release_request' | 'approve_release_request_remove',
    values: Record<string, string>,
    success: string,
  ) {
    setSaving(true)
    setError(null)
    setMessage(null)
    const result = await supabase.rpc(functionName, values)
    setSaving(false)
    if (result.error) return setError(result.error.message)
    setMessage(success)
    setSelectedId(null)
    await load()
  }

  async function approveReplacement(event: FormEvent) {
    event.preventDefault()
    if (!selected || !replacement || hardConflict) return
    if (needsOverride && (!overrideConfirmed || !overrideReason.trim())) {
      return setError('Confirm the availability override and provide a written reason.')
    }
    if (!window.confirm(`Approve and replace ${selected.employee_name} with ${replacement.full_name}?`)) return
    setSaving(true)
    setError(null)
    setMessage(null)
    const result = await supabase.rpc('approve_release_request_replace', {
      p_request_id: selected.request_id,
      p_replacement_staff_id: replacement.staff_id,
      p_override_confirmed: overrideConfirmed,
      p_override_reason: overrideReason || null,
      p_approval_reason: approvalReason,
    })
    setSaving(false)
    if (result.error) return setError(result.error.message)
    setMessage('Request approved and replacement completed atomically.')
    setSelectedId(null)
    await load()
  }

  return (
    <div>
      <h1 className="text-3xl font-bold">Release requests</h1>
      <p className="mt-2 text-slate-600">Review requests and resolve staffing in one controlled workflow.</p>
      {message && <p className="mt-4 rounded-lg bg-green-50 p-3 text-green-900" role="status">{message}</p>}
      {error && <div className="mt-4"><ErrorState message={error} retry={() => void load()} /></div>}

      <div className="card mt-6">
        <label className="font-medium">
          Status
          <select
            className="field max-w-xs"
            value={filter}
            onChange={(event) => setFilter(event.target.value as ReleaseRequestStatus | 'ALL')}
          >
            <option value="PENDING">Pending</option>
            <option value="APPROVED">Approved</option>
            <option value="REJECTED">Rejected</option>
            <option value="CANCELLED">Cancelled</option>
            <option value="ALL">All statuses</option>
          </select>
        </label>
      </div>

      {loading ? <div className="mt-6"><LoadingState /></div> : filtered.length === 0 ? (
        <EmptyState title={`No ${filter === 'ALL' ? '' : filter.toLowerCase()} requests`} />
      ) : (
        <div className="mt-6 grid gap-4">
          {filtered.map((request) => (
            <article className="card" key={request.request_id}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 className="font-semibold">{request.employee_name} · {request.shift_title}</h2>
                  <p className="mt-1 text-sm text-slate-600">{shiftSummary(request)}</p>
                  <p className="mt-2 text-sm"><strong>Reason:</strong> {request.reason}</p>
                </div>
                <ReleaseRequestStatusBadge status={request.status} />
              </div>
              <div className="mt-4">
                <button className="button-secondary" onClick={() => setSelectedId(request.request_id)}>
                  Open request and shift
                </button>
              </div>
            </article>
          ))}
        </div>
      )}

      {selected && (
        <section className="card mt-8" aria-labelledby="request-detail-heading">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 id="request-detail-heading" className="text-xl font-semibold">{selected.employee_name}</h2>
              <h3 className="mt-1 font-medium">{selected.shift_title}</h3>
              <p className="mt-1 text-sm text-slate-600">{shiftSummary(selected)}</p>
            </div>
            <button className="button-secondary" onClick={() => setSelectedId(null)}>Close</button>
          </div>
          <dl className="mt-4 grid gap-2 text-sm sm:grid-cols-2">
            <div><dt className="font-medium">Request reason</dt><dd>{selected.reason}</dd></div>
            <div><dt className="font-medium">Submitted</dt><dd>{displayTimestamp(selected.submitted_at)}</dd></div>
            {selected.note && <div><dt className="font-medium">Employee note</dt><dd>{selected.note}</dd></div>}
            <div><dt className="font-medium">Assignment</dt><dd>{selected.assignment_kind.toLowerCase()} · {selected.assignment_active ? 'Active' : 'Removed'}</dd></div>
          </dl>

          {selected.status === 'PENDING' ? (
            <>
              <div className="mt-6 flex flex-wrap gap-3">
                <button className="button-secondary" disabled={saving} onClick={() => void reject()}>Reject</button>
                <button className="button-secondary" disabled={saving} onClick={() => void approveRemoval()}>
                  Approve and remove
                </button>
              </div>

              <form className="mt-8 grid gap-4 border-t pt-6" onSubmit={approveReplacement}>
                <h3 className="text-lg font-semibold">Approve and replace</h3>
                <label className="font-medium">
                  Replacement employee
                  <select
                    className="field"
                    required
                    value={replacementStaffId}
                    onChange={(event) => {
                      setReplacementStaffId(event.target.value)
                      setOverrideConfirmed(false)
                      setOverrideReason('')
                    }}
                  >
                    <option value="">Select replacement</option>
                    {candidates.map((candidate) => (
                      <option
                        key={candidate.staff_id}
                        value={candidate.staff_id}
                        disabled={candidate.conflicts.some((conflict) => !conflict.overridable)}
                      >
                        {candidate.full_name}
                        {candidate.conflicts.length === 0 ? ' · Fully available' : ` · ${candidate.conflicts.map((conflict) => conflict.code).join(', ')}`}
                      </option>
                    ))}
                  </select>
                </label>
                {replacement && (
                  replacement.conflicts.length === 0 ? (
                    <p className="rounded-lg bg-green-50 p-3 text-sm text-green-900">Eligible and fully available.</p>
                  ) : (
                    <div className={`rounded-lg p-3 text-sm ${hardConflict ? 'bg-red-50 text-red-900' : 'bg-amber-50 text-amber-950'}`}>
                      <p className="font-medium">{hardConflict ? 'This employee cannot be selected' : 'Availability override required'}</p>
                      <ul className="mt-2 list-disc pl-5">
                        {replacement.conflicts.map((conflict) => (
                          <li key={conflict.code}>{conflict.message}{!conflict.overridable && ' (cannot override)'}</li>
                        ))}
                      </ul>
                    </div>
                  )
                )}
                {needsOverride && !hardConflict && (
                  <>
                    <label className="flex items-start gap-2 font-medium">
                      <input
                        className="mt-1"
                        type="checkbox"
                        checked={overrideConfirmed}
                        onChange={(event) => setOverrideConfirmed(event.target.checked)}
                      />
                      I confirm this availability override
                    </label>
                    <label className="font-medium">
                      Override reason
                      <textarea
                        className="field min-h-20"
                        required
                        value={overrideReason}
                        onChange={(event) => setOverrideReason(event.target.value)}
                      />
                    </label>
                  </>
                )}
                <label className="font-medium">
                  Approval and replacement reason
                  <textarea
                    className="field min-h-20"
                    required
                    value={approvalReason}
                    onChange={(event) => setApprovalReason(event.target.value)}
                  />
                </label>
                <div>
                  <button
                    className="button"
                    disabled={saving || !replacement || hardConflict || (needsOverride && !overrideConfirmed)}
                  >
                    {saving ? 'Resolving…' : 'Confirm replacement'}
                  </button>
                </div>
              </form>
            </>
          ) : (
            <div className="mt-6 rounded-lg bg-slate-50 p-4 text-sm">
              <ReleaseRequestStatusBadge status={selected.status} />
              {selected.resolution_reason && <p className="mt-2"><strong>Resolution:</strong> {selected.resolution_reason}</p>}
              {selected.resolved_by_name && <p className="mt-1">Resolved by {selected.resolved_by_name}</p>}
            </div>
          )}
        </section>
      )}
    </div>
  )
}
