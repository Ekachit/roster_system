import { render, screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import type { ScheduledHoursRow } from '../lib/types'
import { ReportExplanation, ReportResults } from './ScheduledHoursPage'

const rows: ScheduledHoursRow[] = [
  {
    assignment_id: 'assignment-1',
    staff_id: 'staff-1',
    employee_name: 'Synthetic Employee One',
    employee_email: 'employee.one@example.test',
    shift_id: 'shift-1',
    local_date: '2026-08-10',
    start_time: '09:00:00',
    end_time: '10:30:00',
    duration_minutes: 90,
    location_id: 'location-1',
    location_name: 'Clayton',
    activity_type_id: 'activity-1',
    activity_name: 'Training',
    shift_status: 'PUBLISHED',
    assignment_status: 'ASSIGNED',
  },
  {
    assignment_id: 'assignment-2',
    staff_id: 'staff-1',
    employee_name: 'Synthetic Employee One',
    employee_email: 'employee.one@example.test',
    shift_id: 'shift-2',
    local_date: '2026-08-10',
    start_time: '10:30:00',
    end_time: '12:00:00',
    duration_minutes: 90,
    location_id: 'location-1',
    location_name: 'Clayton',
    activity_type_id: 'activity-2',
    activity_name: 'Event',
    shift_status: 'PUBLISHED',
    assignment_status: 'ASSIGNED',
  },
  {
    assignment_id: 'assignment-3',
    staff_id: 'staff-2',
    employee_name: 'Synthetic Employee Two',
    employee_email: 'employee.two@example.test',
    shift_id: 'shift-3',
    local_date: '2026-08-11',
    start_time: '13:00:00',
    end_time: '14:00:00',
    duration_minutes: 60,
    location_id: 'location-2',
    location_name: 'Caulfield',
    activity_type_id: 'activity-1',
    activity_name: 'Training',
    shift_status: 'PUBLISHED',
    assignment_status: 'ASSIGNED',
  },
]

describe('scheduled-hours report results', () => {
  it('clarifies that current scheduled hours are not attendance or actual worked hours', () => {
    render(<ReportExplanation />)

    expect(screen.getByText(/current scheduled hours for published shifts with active assignments/))
      .toBeInTheDocument()
    expect(screen.getByText(/does not represent attendance, actual worked hours or payroll/))
      .toBeInTheDocument()
    expect(screen.getByText(/historical removal remains available in audit history/))
      .toBeInTheDocument()
    expect(screen.getByText(/future attendance-confirmation workflow/)).toBeInTheDocument()
  })

  it('summarises multiple and back-to-back shifts by employee using exact minutes', () => {
    render(<ReportResults rows={rows} />)
    const summary = screen.getAllByRole('table')[0]
    const employeeOne = within(summary).getByText('Synthetic Employee One').closest('tr')
    const employeeTwo = within(summary).getByText('Synthetic Employee Two').closest('tr')

    expect(employeeOne).toHaveTextContent('2')
    expect(employeeOne).toHaveTextContent('3 hr')
    expect(employeeTwo).toHaveTextContent('1')
    expect(employeeTwo).toHaveTextContent('1 hr')
    expect(screen.getByText('09:00–10:30')).toBeInTheDocument()
    expect(screen.getByText('10:30–12:00')).toBeInTheDocument()
  })

  it('shows detailed location, activity, shift status, and assignment status', () => {
    render(<ReportResults rows={[rows[0]]} />)

    expect(screen.getByText('Clayton')).toBeInTheDocument()
    expect(screen.getByText('Training')).toBeInTheDocument()
    expect(screen.getByText('Published')).toBeInTheDocument()
    expect(screen.getByText('Assigned')).toBeInTheDocument()
  })

  it('documents cancelled and removed exclusion in the empty state', () => {
    render(<ReportResults rows={[]} />)

    expect(screen.getByText('No scheduled hours match these filters')).toBeInTheDocument()
    expect(screen.getByText(/Cancelled shifts and removed assignments are not included/)).toBeInTheDocument()
  })
})
