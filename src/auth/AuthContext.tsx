import type { Session } from '@supabase/supabase-js'
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { supabase } from '../lib/supabase'
import type { Profile } from '../lib/types'

interface AuthState {
  session: Session | null
  profile: Profile | null
  loading: boolean
  error: string | null
  refreshProfile: () => Promise<void>
  signOut: () => Promise<void>
}

const AuthContext = createContext<AuthState | undefined>(undefined)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const loadProfile = useCallback(async (currentSession: Session | null) => {
    if (!currentSession) {
      setProfile(null)
      setError(null)
      return
    }
    const { data, error: profileError } = await supabase.rpc('current_access_profile')
    const accessProfile = Array.isArray(data) ? data[0] : data
    setProfile((accessProfile as Profile | null) ?? null)
    setError(profileError?.message ?? null)
  }, [])

  const refreshProfile = useCallback(async () => {
    await loadProfile(session)
  }, [loadProfile, session])

  useEffect(() => {
    let mounted = true
    void supabase.auth.getSession().then(async ({ data }) => {
      if (!mounted) return
      setSession(data.session)
      await loadProfile(data.session)
      if (mounted) setLoading(false)
    })
    const { data: listener } = supabase.auth.onAuthStateChange((_event, nextSession) => {
      setSession(nextSession)
      setLoading(true)
      void loadProfile(nextSession).finally(() => setLoading(false))
    })
    return () => {
      mounted = false
      listener.subscription.unsubscribe()
    }
  }, [loadProfile])

  const value = useMemo<AuthState>(() => ({
    session,
    profile,
    loading,
    error,
    refreshProfile,
    signOut: async () => { await supabase.auth.signOut() },
  }), [error, loading, profile, refreshProfile, session])

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

// The hook intentionally lives beside its provider so the context remains private.
// eslint-disable-next-line react-refresh/only-export-components
export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used inside AuthProvider')
  return context
}
