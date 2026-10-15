import { test } from 'node:test'
import assert from 'node:assert/strict'
import { course, professors } from '@shared/domain'
import type { Section } from '@shared/types'
import { fits, formatLabel, meetingDays, titleCase } from '../src/schedule'
import { demoData, demoSeats, FALL } from '../src/demo-data'

const section = (formats: string[], meetings: string[]): Section => ({ crn: '1', title: '', start: '', end: '', status: 'O', formats, meetings })

test('meeting days are read from the shared meeting descriptions', () => {
  const rows = demoData.schedules[FALL.termCode]
  const marisol = professors(rows, course('ETH 014')).find(p => p.name === 'Marisol Quintero-Hale')!
  assert.deepEqual([...meetingDays(marisol.sections[0])], ['Mon', 'Wed'])
})

test('day filter matches the Mac app: every picked day, online always fits', () => {
  const mw = section(['L'], ['Mon, Wed 8:00 AM – 9:25 AM C 323'])
  assert.equal(fits(mw, []), true)
  assert.equal(fits(mw, ['Mon']), true)
  assert.equal(fits(mw, ['Mon', 'Wed']), true)
  assert.equal(fits(mw, ['Mon', 'Fri']), false)
  assert.equal(fits(section(['OD'], []), ['Fri']), true)
  assert.equal(fits(section(['L'], []), ['Mon']), false)
  // A hybrid section's online part adds no days; its campus meeting still counts.
  assert.equal(fits(section(['HY'], ['Online ASYNCH Needs Assignment', 'Wed 10:30 AM – 1:20 PM R 516']), ['Wed']), true)
})

test('format labels and title case', () => {
  assert.equal(formatLabel(section(['OD'], [])), 'Online · async')
  assert.equal(formatLabel(section(['HY'], [])), 'Hybrid')
  assert.equal(formatLabel(section(['OL'], [])), 'Online · live')
  assert.equal(formatLabel(section(['L'], [])), 'In person')
  assert.equal(titleCase('SINGLE VARIABLE CALCULUS I'), 'Single variable calculus I')
})

test('every sample section has seats, and closed sections have none open', () => {
  for (const row of demoData.schedules[FALL.termCode]) {
    const seats = demoSeats[String(row.crn)]
    assert.ok(seats, `CRN ${row.crn} has no seats`)
    if (row.fwSectOpenInd === 'C') assert.equal(seats.open, 0)
    else assert.ok(seats.open > 0)
  }
})
