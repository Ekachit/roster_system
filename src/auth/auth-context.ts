import type { Session } from '@supabase/supabase-js'
import { createContext, useContext } from 'react'
import type { Profile } from '../lib/types'

export interface AuthState {
  session: Session | null
  profile: Profile | null
  loading: boolean
  error: string | null
  refreshProfile: () => Promise<void>
  signOut: () => Promise<void>
}

export const AuthContext = createContext<AuthState | undefined>(undefined)

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used inside AuthProvider')
  return context
}
