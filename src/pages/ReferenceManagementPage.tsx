import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { EmptyState, ErrorState, LoadingState } from '../components/States'
import { supabase } from '../lib/supabase'
import type { ReferenceRecord } from '../lib/types'

type ReferenceTable = 'locations' | 'activity_types'

export function ReferenceManagementPage({ table, title }: { table: ReferenceTable; title: string }) {
  const [rows, setRows] = useState<ReferenceRecord[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [name, setName] = useState('')
  const [start, setStart] = useState('')
  const [end, setEnd] = useState('')
  const [editing, setEditing] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    const { data, error: queryError } = await supabase.from(table).select('*').order('name')
    setRows((data as ReferenceRecord[] | null) ?? [])
    setError(queryError?.message ?? null)
    setLoading(false)
  }, [table])

  useEffect(() => { void load() }, [load])

  function reset() {
    setName(''); setStart(''); setEnd(''); setEditing(null)
  }

  async function save(event: FormEvent) {
    event.preventDefault()
    setError(null); setMessage(null)
    const payload = { name: name.trim(), default_start_time: start || null, default_end_time: end || null }
    const result = editing
      ? await supabase.from(table).update(payload).eq('id', editing)
      : await supabase.from(table).insert(payload)
    if (result.error) setError(result.error.message)
    else { setMessage(`${title.slice(0, -1)} saved.`); reset(); await load() }
  }

  async function toggle(row: ReferenceRecord) {
    setMessage(null)
    if (row.is_active && !window.confirm(`Deactivate ${row.name}? Existing roster history will be preserved, but it will no longer be available for new shifts.`)) return
    const { error: updateError } = await supabase.from(table).update({ is_active: !row.is_active }).eq('id', row.id)
    if (updateError) setError(updateError.message)
    else { setMessage(`${row.name} ${row.is_active ? 'deactivated' : 'activated'}.`); await load() }
  }

  return (
    <>
      <h1 className="text-3xl font-bold">{title}</h1>
      <p className="mt-2 text-slate-600">Manage active options and optional default shift times.</p>
      {message && <p className="mt-4 rounded-lg bg-green-50 p-3 text-green-900" role="status">{message}</p>}
      {error && <div className="mt-4"><ErrorState message={error} retry={() => void load()} /></div>}
      <form onSubmit={save} className="card mt-6 grid gap-4 sm:grid-cols-4">
        <label className="font-medium sm:col-span-2">Name<input className="field" maxLength={100} required value={name} onChange={(e) => setName(e.target.value)} /></label>
        <label className="font-medium">Default start<input className="field" type="time" value={start} onChange={(e) => setStart(e.target.value)} /></label>
        <label className="font-medium">Default end<input className="field" type="time" value={end} onChange={(e) => setEnd(e.target.value)} /></label>
        <div className="flex gap-2 sm:col-span-4"><button className="button">{editing ? 'Update' : 'Add'}</button>{editing && <button type="button" className="button-secondary" onClick={reset}>Cancel</button>}</div>
      </form>
      <div className="mt-6">
        {loading ? <LoadingState /> : rows.length === 0 ? <EmptyState title={`No ${title.toLowerCase()} configured`} /> : (
          <ul className="grid gap-3">{rows.map((row) => <li className="card flex flex-wrap items-center justify-between gap-3" key={row.id}><div><h2 className="font-semibold">{row.name}</h2><p className="text-sm text-slate-600">{row.is_active ? 'Active' : 'Inactive'}{row.default_start_time && row.default_end_time ? ` · ${row.default_start_time.slice(0, 5)}–${row.default_end_time.slice(0, 5)}` : ''}</p></div><div className="flex gap-2"><button className="button-secondary" onClick={() => { setEditing(row.id); setName(row.name); setStart(row.default_start_time?.slice(0, 5) ?? ''); setEnd(row.default_end_time?.slice(0, 5) ?? '') }}>Edit</button><button className="button-secondary" onClick={() => void toggle(row)}>{row.is_active ? 'Deactivate' : 'Activate'}</button></div></li>)}</ul>
        )}
      </div>
    </>
  )
}
