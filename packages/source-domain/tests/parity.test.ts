import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { course, professors, resolve, suggestions, eligible } from '../src/index'
import { demoData, FALL } from '../../../services/web-api/tests/source-data'
const expected = JSON.parse(readFileSync(new URL('./parity.json', import.meta.url), 'utf8'))
test('extracted helpers match the recorded frontend baseline on fictional input', () => {
  const rows = demoData.schedules[FALL.termCode]
  assert.deepEqual(JSON.parse(JSON.stringify({ courses: ['MATH5A', 'ETH014', 'POLS C1000'].map(course), suggestions: suggestions('math', rows), resolved: resolve('math005a', rows), professors: professors(rows, course('MATH5A')), eligible: eligible('Lena Whitcombe', demoData.profiles) })), expected)
})
