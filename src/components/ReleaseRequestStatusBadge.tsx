import type { ReleaseRequestStatus } from '../lib/types'

const styles: Record<ReleaseRequestStatus, string> = {
  PENDING: 'bg-amber-100 text-amber-900',
  APPROVED: 'bg-green-100 text-green-900',
  REJECTED: 'bg-red-100 text-red-900',
  CANCELLED: 'bg-slate-200 text-slate-900',
}

export function ReleaseRequestStatusBadge({ status }: { status: ReleaseRequestStatus }) {
  return (
    <span className={`inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ${styles[status]}`}>
      {status[0] + status.slice(1).toLowerCase()}
    </span>
  )
}
