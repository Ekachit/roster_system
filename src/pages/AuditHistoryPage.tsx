import { useCallback, useEffect, useState } from 'react'
import { EmptyState, ErrorState, LoadingState } from '../components/States'
import { ROSTER_TIME_ZONE } from '../domain/availability'
import { supabase } from '../lib/supabase'
import type { AuditHistoryRecord } from '../lib/types'

const actions = [
  'AVAILABILITY_CREATED',
  'AVAILABILITY_UPDATED',
  'AVAILABILITY_REMOVED',
  'SHIFT_CREATED',
  'SHIFT_EDITED',
  'SHIFT_PUBLISHED',
  'SHIFT_UNPUBLISHED',
  'SHIFT_CANCELLED',
  'EMPLOYEE_ASSIGNED',
  'EMPLOYEE_REMOVED',
  'EMPLOYEE_REPLACED',
  'ASSIGNMENT_OVERRIDDEN',
  'ASSIGNMENT_ACKNOWLEDGED',
  'RELEASE_REQUEST_CREATED',
  'RELEASE_REQUEST_APPROVED',
  'RELEASE_REQUEST_REJECTED',
  'RELEASE_REQUEST_CANCELLED',
]

const entityTypes = [
  'RECURRING_AVAILABILITY',
  'AVAILABILITY_EXCEPTION',
  'SHIFT',
  'ASSIGNMENT',
  'RELEASE_REQUEST',
]

function displayTimestamp(timestamp: string) {
  return new Intl.DateTimeFormat('en-AU', {
    timeZone: ROSTER_TIME_ZONE,
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(timestamp))
}

function displayAction(action: string) {
  return action.split('_').map((part) => part[0] + part.slice(1).toLowerCase()).join(' ')
}

function hasData(value: Record<string, unknown>) {
  return Object.keys(value).length > 0
}

export function AuditHistoryPage() {
  const [records, setRecords] = useState<AuditHistoryRecord[]>([])
  const [action, setAction] = useState('')
  const [entityType, setEntityType] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    const result = await supabase.rpc('supervisor_audit_history', {
      p_action: action || null,
      p_entity_type: entityType || null,
      p_limit: 200,
    })
    setRecords((result.data as AuditHistoryRecord[] | null) ?? [])
    setError(result.error?.message ?? null)
    setLoading(false)
  }, [action, entityType])

  useEffect(() => { void load() }, [load])

  return (
    <div>
      <h1 className="text-3xl font-bold">Audit history</h1>
      <p className="mt-2 text-slate-600">
        Append-only history of roster, availability, acknowledgement, override, and release actions.
        Timestamps use {ROSTER_TIME_ZONE}.
      </p>
      {error && <div className="mt-4"><ErrorState message={error} retry={() => void load()} /></div>}

      <div className="card mt-6 grid gap-4 sm:grid-cols-2">
        <label className="font-medium">
          Action
          <select className="field" value={action} onChange={(event) => setAction(event.target.value)}>
            <option value="">All actions</option>
            {actions.map((item) => <option key={item} value={item}>{displayAction(item)}</option>)}
          </select>
        </label>
        <label className="font-medium">
          Entity type
          <select className="field" value={entityType} onChange={(event) => setEntityType(event.target.value)}>
            <option value="">All entity types</option>
            {entityTypes.map((item) => <option key={item} value={item}>{displayAction(item)}</option>)}
          </select>
        </label>
      </div>

      {loading ? <div className="mt-6"><LoadingState /></div> : records.length === 0 ? (
        <EmptyState title="No audit events match these filters" />
      ) : (
        <div className="mt-6 grid gap-3">
          {records.map((record) => (
            <article className="card p-4" key={record.audit_id}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <h2 className="font-semibold">{displayAction(record.action)}</h2>
                  <p className="mt-1 text-sm text-slate-600">
                    {record.actor_name} · {displayTimestamp(record.created_at)}
                  </p>
                </div>
                <span className="rounded-full bg-slate-100 px-2.5 py-1 text-xs font-semibold text-slate-800">
                  {displayAction(record.entity_type)}
                </span>
              </div>
              <dl className="mt-3 grid gap-2 text-sm sm:grid-cols-2">
                <div><dt className="font-medium">Entity ID</dt><dd className="break-all font-mono text-xs">{record.entity_id ?? 'Not recorded'}</dd></div>
                {record.subject_name && <div><dt className="font-medium">Employee</dt><dd>{record.subject_name}</dd></div>}
                {record.reason && <div className="sm:col-span-2"><dt className="font-medium">Reason</dt><dd>{record.reason}</dd></div>}
              </dl>
              {(hasData(record.before_data) || hasData(record.after_data)) && (
                <details className="mt-3 text-sm">
                  <summary className="cursor-pointer font-medium">Before / after data</summary>
                  <div className="mt-2 grid gap-2 sm:grid-cols-2">
                    <pre className="overflow-x-auto rounded bg-slate-50 p-2 text-xs">{JSON.stringify(record.before_data, null, 2)}</pre>
                    <pre className="overflow-x-auto rounded bg-slate-50 p-2 text-xs">{JSON.stringify(record.after_data, null, 2)}</pre>
                  </div>
                </details>
              )}
            </article>
          ))}
        </div>
      )}
    </div>
  )
}
