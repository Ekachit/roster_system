import { useState, type FormEvent } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '../auth/auth-context'
import { env } from '../lib/env'
import { supabase } from '../lib/supabase'

export function SignInPage() {
  const { session, loading } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [message, setMessage] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  if (!loading && session) return <Navigate to="/" replace />

  async function submit(event: FormEvent) {
    event.preventDefault()
    setSubmitting(true)
    setMessage(null)
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password })
    setSubmitting(false)
    if (error) setMessage('Sign-in failed. Check your details or contact your supervisor.')
  }

  return (
    <main className="grid min-h-screen place-items-center px-4 py-10">
      <form onSubmit={submit} className="card w-full max-w-md" aria-labelledby="sign-in-heading">
        <p className="font-semibold text-blue-800">AI Fitness Zone</p>
        <h1 id="sign-in-heading" className="mt-1 text-3xl font-bold">Staff sign in</h1>
        <p className="mt-2 text-slate-600">Access is limited to staff approved by a supervisor. There is no public registration.</p>
        {!env.isConfigured && <p className="mt-4 rounded-lg bg-amber-50 p-3 text-sm text-amber-900" role="alert">Supabase environment variables are not configured.</p>}
        {message && <p className="mt-4 rounded-lg bg-red-50 p-3 text-sm text-red-900" role="alert">{message}</p>}
        <label className="mt-6 block font-medium">Email<input className="field" type="email" autoComplete="email" maxLength={320} required value={email} onChange={(event) => setEmail(event.target.value)} /></label>
        <label className="mt-4 block font-medium">Password<input className="field" type="password" autoComplete="current-password" required value={password} onChange={(event) => setPassword(event.target.value)} /></label>
        <button className="button mt-6 w-full" disabled={submitting || !env.isConfigured}>{submitting ? 'Signing in…' : 'Sign in'}</button>
      </form>
    </main>
  )
}
