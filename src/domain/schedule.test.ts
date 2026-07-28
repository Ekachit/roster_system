import { afterEach, describe, expect, it } from 'vitest'
import { melbourneScheduleWeek } from './schedule'

const originalTimeZone = process.env.TZ

afterEach(() => {
  process.env.TZ = originalTimeZone
})

describe('Melbourne scheduled-hours default week', () => {
  it('uses the containing Monday-to-Sunday week on a Melbourne Monday', () => {
    expect(melbourneScheduleWeek(new Date('2026-07-26T14:30:00Z'))).toEqual({
      startDate: '2026-07-27',
      endDate: '2026-08-02',
    })
  })

  it('uses the containing Monday-to-Sunday week on a Melbourne Sunday', () => {
    expect(melbourneScheduleWeek(new Date('2026-08-02T13:30:00Z'))).toEqual({
      startDate: '2026-07-27',
      endDate: '2026-08-02',
    })
  })

  it('changes weeks at the Melbourne Sunday-to-Monday boundary', () => {
    expect(melbourneScheduleWeek(new Date('2026-07-26T13:59:00Z'))).toEqual({
      startDate: '2026-07-20',
      endDate: '2026-07-26',
    })
    expect(melbourneScheduleWeek(new Date('2026-07-26T14:01:00Z'))).toEqual({
      startDate: '2026-07-27',
      endDate: '2026-08-02',
    })
  })

  it('remains correct during Melbourne daylight-saving time', () => {
    expect(melbourneScheduleWeek(new Date('2026-01-04T13:15:00Z'))).toEqual({
      startDate: '2026-01-05',
      endDate: '2026-01-11',
    })
    expect(melbourneScheduleWeek(new Date('2026-01-11T12:45:00Z'))).toEqual({
      startDate: '2026-01-05',
      endDate: '2026-01-11',
    })
  })

  it('ignores a foreign system timezone when its calendar date differs from Melbourne', () => {
    process.env.TZ = 'America/Los_Angeles'
    const instant = new Date('2026-07-26T14:30:00Z')

    expect(new Intl.DateTimeFormat('en-CA', {
      timeZone: 'America/Los_Angeles',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).format(instant)).toBe('2026-07-26')
    expect(melbourneScheduleWeek(instant)).toEqual({
      startDate: '2026-07-27',
      endDate: '2026-08-02',
    })
  })
})
