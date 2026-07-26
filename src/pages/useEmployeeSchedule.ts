import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { EmployeeScheduleItem } from '../lib/types'

export function useEmployeeSchedule() {
  const [items, setItems] = useState<EmployeeScheduleItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    const result = await supabase.rpc('employee_schedule')
    setItems((result.data as EmployeeScheduleItem[] | null) ?? [])
    setError(result.error?.message ?? null)
    setLoading(false)
  }, [])

  useEffect(() => { void load() }, [load])
  return { items, loading, error, load }
}
