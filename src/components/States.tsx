import type { ReactNode } from 'react'

export function LoadingState({ label = 'Loading…' }: { label?: string }) {
  return <div className="card" role="status" aria-live="polite">{label}</div>
}

export function ErrorState({ message, retry }: { message: string; retry?: () => void }) {
  return (
    <div className="card border-red-200 bg-red-50" role="alert">
      <h2 className="font-semibold text-red-900">Something went wrong</h2>
      <p className="mt-1 text-red-800">{message}</p>
      {retry && <button className="button mt-4" onClick={retry}>Try again</button>}
    </div>
  )
}

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return <div className="card text-center"><h2 className="font-semibold">{title}</h2>{children && <div className="mt-2 text-slate-600">{children}</div>}</div>
}

export function UnauthorisedState({ reason = 'unapproved' }: { reason?: 'unapproved' | 'inactive' | 'email-mismatch' }) {
  const heading = reason === 'inactive'
    ? 'Account inactive'
    : reason === 'email-mismatch'
      ? 'Approved email mismatch'
      : 'Access not approved'
  const message = reason === 'inactive'
    ? 'Your account has been deactivated. Contact your supervisor if you believe this is an error.'
    : reason === 'email-mismatch'
      ? 'Your current sign-in email no longer matches your approved staff email. Contact the system owner to complete the administrator unlink-and-relink process.'
      : 'Your signed-in email is not linked to an approved staff profile. Ask your supervisor to approve it.'
  return (
    <div className="card mx-auto max-w-xl" role="alert">
      <h1 className="text-2xl font-bold">{heading}</h1>
      <p className="mt-2 text-slate-600">{message}</p>
    </div>
  )
}
