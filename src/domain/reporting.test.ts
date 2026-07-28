import { describe, expect, it } from 'vitest'
import type { ScheduledHoursRow } from '../lib/types'
import {
  formatDurationMinutes,
  serializeCsvCell,
  scheduledHoursCsv,
  scheduledHoursFilename,
} from './reporting'

const row: ScheduledHoursRow = {
  assignment_id: 'assignment-1',
  staff_id: 'staff-1',
  employee_name: 'Synthetic Employee',
  employee_email: 'synthetic.employee@example.test',
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
}

describe('scheduled-hours reporting utilities', () => {
  it('formats integer-minute durations without floating-point output', () => {
    expect(formatDurationMinutes(30)).toBe('30 min')
    expect(formatDurationMinutes(60)).toBe('1 hr')
    expect(formatDurationMinutes(150)).toBe('2 hr 30 min')
  })

  it('preserves ordinary text, punctuation, and internal line breaks', () => {
    expect(serializeCsvCell('plain')).toBe('plain')
    expect(serializeCsvCell('Clayton, Victoria')).toBe('"Clayton, Victoria"')
    expect(serializeCsvCell('She said "hello"')).toBe('"She said ""hello"""')
    expect(serializeCsvCell('line one\r\nline two')).toBe('"line one\r\nline two"')
    expect(serializeCsvCell(90)).toBe('90')
  })

  it.each([
    ['employee name beginning =', '=2+2', "'=2+2"],
    ['employee email beginning +', '+cmd@example.test', "'+cmd@example.test"],
    ['location beginning -', '-1+1', "'-1+1"],
    ['activity beginning @', '@SUM(1,1)', '"\'@SUM(1,1)"'],
    ['status beginning tab', '\tPUBLISHED', '"\'\tPUBLISHED"'],
    ['status beginning carriage return', '\rASSIGNED', '"\'\rASSIGNED"'],
    ['status beginning line feed', '\nASSIGNED', '"\'\nASSIGNED"'],
    ['full-width equals', '\uFF1DSUM(1,1)', '"\'\uFF1DSUM(1,1)"'],
    ['full-width plus', '\uFF0B1+1', "'\uFF0B1+1"],
    ['full-width minus', '\uFF0D1+1', "'\uFF0D1+1"],
    ['full-width at', '\uFF20SUM(1,1)', '"\'\uFF20SUM(1,1)"'],
  ])('protects %s before delimiter escaping', (_label, input, expected) => {
    expect(serializeCsvCell(input)).toBe(expected)
  })

  it('protects every exported text field while retaining exact columns and punctuation', () => {
    const csv = scheduledHoursCsv([{
      ...row,
      employee_name: '=SUM(1,1), "Quoted"\r\nEmployee',
      employee_email: '+formula@example.test',
      location_name: '\uFF1DClayton, Victoria',
      activity_name: '\nTraining "A"',
      shift_status: '\uFF0BPUBLISHED',
      assignment_status: '\rASSIGNED',
    } as unknown as ScheduledHoursRow])

    expect(csv.startsWith(
      '\uFEFFEmployee name,Employee email,Date,Start time,End time,Duration,Location,Activity type,Shift status,Assignment status\r\n',
    )).toBe(true)
    expect(csv).toContain(
      '"\'=SUM(1,1), ""Quoted""\r\nEmployee",\'+formula@example.test,2026-08-10,09:00,10:30,90,"\'＝Clayton, Victoria","\'\nTraining ""A""",\'＋PUBLISHED,"\'\rASSIGNED"\r\n',
    )
    expect(csv).not.toContain('supervisor')
    expect(csv).not.toContain('notes')
  })

  it('uses the selected ISO date range in the filename', () => {
    expect(scheduledHoursFilename('2026-08-10', '2026-08-16'))
      .toBe('scheduled-hours_2026-08-10_to_2026-08-16.csv')
  })
})
