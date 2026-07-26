import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { EmptyState, ErrorState, LoadingState, UnauthorisedState } from './States'

describe('shared application states', () => {
  it('announces loading and errors accessibly', () => {
    const { rerender } = render(<LoadingState />)
    expect(screen.getByRole('status')).toHaveTextContent('Loading')
    rerender(<ErrorState message="Network unavailable" />)
    expect(screen.getByRole('alert')).toHaveTextContent('Network unavailable')
  })
  it('renders empty and inactive states', () => {
    const { rerender } = render(<EmptyState title="No staff" />)
    expect(screen.getByRole('heading', { name: 'No staff' })).toBeInTheDocument()
    rerender(<UnauthorisedState reason="inactive" />)
    expect(screen.getByRole('alert')).toHaveTextContent('Account inactive')
  })
})
