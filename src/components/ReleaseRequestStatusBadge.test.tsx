import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { ReleaseRequestStatusBadge } from './ReleaseRequestStatusBadge'

describe('ReleaseRequestStatusBadge', () => {
  it.each([
    ['PENDING', 'Pending', 'bg-amber-100'],
    ['APPROVED', 'Approved', 'bg-green-100'],
    ['REJECTED', 'Rejected', 'bg-red-100'],
    ['CANCELLED', 'Cancelled', 'bg-slate-200'],
  ] as const)('renders %s clearly', (status, label, className) => {
    const { container } = render(<ReleaseRequestStatusBadge status={status} />)
    expect(screen.getByText(label)).toBeInTheDocument()
    expect(container.firstChild).toHaveClass(className)
  })
})
