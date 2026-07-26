import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import type { EmployeeScheduleItem } from '../lib/types'
import { ScheduleCard } from './EmployeeSchedulePage'

const item: EmployeeScheduleItem = {
  assignment_id: 'assignment-1',
  shift_id: 'shift-1',
  shift_title: 'Synthetic training coverage',
  local_date: '2026-08-10',
  start_time: '09:00:00',
  end_time: '10:30:00',
  location_name: 'Clayton',
  activity_name: 'Training',
  notes: 'Synthetic notes',
  assignment_kind: 'REGULAR',
  assignment_status: 'ASSIGNED',
  acknowledged_at: null,
  colleague_names: ['Synthetic Colleague'],
}

describe('employee schedule card', () => {
  it('renders required schedule information in a mobile-friendly single card', () => {
    render(<MemoryRouter><div style={{ width: 320 }}><ScheduleCard item={item} /></div></MemoryRouter>)
    const card = screen.getByTestId('schedule-card')
    expect(card).toHaveTextContent('Synthetic training coverage')
    expect(card).toHaveTextContent('9:00 am–10:30 am')
    expect(card).toHaveTextContent('Clayton')
    expect(card).toHaveTextContent('Training')
    expect(card).toHaveTextContent('Assigned')
    expect(card).toHaveTextContent('Outstanding')
    expect(screen.getByRole('link', { name: 'View shift details' })).toHaveAttribute('href', '/employee/shifts/shift-1')
  })
})
